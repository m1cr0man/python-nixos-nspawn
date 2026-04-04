{ pkgs, lib, config, ... }:

let
  hostConfig = config;
  cfg = config.nixos.containers.instances;

  shared = import ./shared.nix { inherit lib; };

  inherit (shared) ifacePrefix mkNetworkingOpts;

  inherit (lib) mkOption mkEnableOption types mkIf mkMerge mkBefore mkDefault;
  inherit (lib) concatMapStrings attrNames elem optionals;

  yesNo = x: if x then "yes" else "no";

  dynamicAddrsDisabled = inst:
    inst.network == null || inst.network.v4.addrPool == [ ] && inst.network.v6.addrPool == [ ];

  zoneCfg = config.nixos.containers.zones;

  interfaces.containers = attrNames cfg;
  interfaces.zones = attrNames config.nixos.containers.zones;

  mkMatchCfg = type: name:
    assert elem type [ "veth" "zone" ]; {
      Name = "${ifacePrefix type}-${name}";
      Driver = if type == "veth" then "veth" else "bridge";
    };

  mkNetworkCfg = dhcp: { v4Nat, v6Nat }: {
    LinkLocalAddressing = mkDefault "ipv6";
    DHCPServer = yesNo dhcp;
    IPMasquerade =
      if v4Nat && v6Nat then "both"
      else if v4Nat then "ipv4"
      else if v6Nat then "ipv6"
      else "no";
    IPv4Forwarding = "yes";
    IPv6Forwarding = "yes";
    LLDP = "yes";
    EmitLLDP = "customer-bridge";
    IPv6AcceptRA = "no";
    IPv6SendRA = "yes";
  };

  recUpdate3 = a: b: c:
    lib.recursiveUpdate a (lib.recursiveUpdate b c);

  mkForwardPorts = map
    (
      { containerPort ? null, hostPort, protocol }:
      let
        host = toString hostPort;
        container = if containerPort == null then host else toString containerPort;
      in
      "${protocol}:${host}:${container}"
    );

  mkImage = name: config: { container = config.system-config; inherit config; };

  mkContainer = cfg:
    let
      inherit (cfg) container config;
      idmap = lib.optionalString config.userNamespacing ":rootidmap";
    in
    mkMerge [
      {
        execConfig = {
          Boot = false;
          Parameters = "${container.config.system.build.toplevel}/init";
          Ephemeral = yesNo config.ephemeral;
          SystemCallFilter = lib.mkIf (config.systemCallFilter != null) config.systemCallFilter;
          KillSignal = "SIGRTMIN+3";
          PrivateUsers = mkDefault (if config.userNamespacing then "pick" else "no");
          LinkJournal = mkDefault (if config.ephemeral then "auto" else "guest");
        };
        filesConfig = mkMerge [
          {
            PrivateUsersOwnership = mkDefault (if config.userNamespacing then "auto" else "chown");
            Bind = config.bindMounts;
          }
          (mkIf config.sharedNix {
            BindReadOnly = [
              "/nix/store:/nix/store${idmap}"
              "/nix/var/nix/profiles:/nix/var/nix/profiles${idmap}"
            ];
          })
          (mkIf (config.sharedNix && config.mountDaemonSocket) {
            BindReadOnly = [ "/nix/var/nix/db:/nix/var/nix/db${idmap}" ];
            Bind = [ "/nix/var/nix/daemon-socket:/nix/var/nix/daemon-socket${idmap}" ];
          })
        ];
        networkConfig = mkMerge [
          (mkIf (config.bridge != null) {
            Bridge = config.bridge;
          })
          (mkIf (config.zone != null || config.network != null) {
            Private = true;
            VirtualEthernet = "yes";
          })
          (mkIf (config.zone != null) {
            Zone = config.zone;
          })
          (mkIf (config.forwardPorts != [ ]) {
            Port = mkForwardPorts config.forwardPorts;
          })
        ];
      }
      (mkIf (!config.sharedNix) {
        extraDrvConfig =
          let
            info = pkgs.closureInfo {
              rootPaths = [ container.config.system.build.toplevel ];
            };
          in
          pkgs.runCommand "bindmounts.nspawn" { }
            ''
              echo "[Files]" > $out

              cat ${info}/store-paths | while read line
              do
                echo "BindReadOnly=$line:$line${idmap}" >> $out
              done
            '';
      })
    ];

  images = lib.mapAttrs mkImage cfg;
in
{
  options.nixos.containers = {
    zones = mkOption {
      type = types.attrsOf (types.submodule {
        options = mkNetworkingOpts "zone";
      });
      default = { };
      description = ''
        Networking zones for nspawn containers. In this mode, the host-side
        of the virtual ethernet of a machine is managed by an interface named
        `vz-<name>`.
      '';
    };

    instances = mkOption {
      default = { };
      type = types.attrsOf (types.submodule ({ name, config, ... }: {
        options = import ./container-options.nix {
          inherit pkgs lib name config hostConfig;
          declarative = true;
        };
      }));

      description = ''
        Attribute set to define {manpage}`systemd.nspawn(5)`-managed containers. With this attribute-set,
        a network, a shared store and a NixOS configuration can be declared for each running
        container.

        The container's state is managed in `/var/lib/machines/<name>`.
        A machine can be started with the
        `systemd-nspawn@<name>.service`-unit, during runtime it can
        be accessed with {manpage}`machinectl(1)`.

        Please note that if both [](#opt-nixos.containers.instances._name_.network)
        & [](#opt-nixos.containers.instances._name_.zone) are
        `null`, the container will use the host's network.
      '';
    };

    enableAutostartService = (mkEnableOption "autostarting of imperative containers") // {
      default = true;
    };
  };

  config = mkMerge [
    (mkIf (config.nixos.containers.enableAutostartService) {
      systemd.services.nixos-nspawn-autostart = {
        description = "Automatically starts imperative containers on system boot";
        wantedBy = [ "machines.target" ];
        before = [ "machines.target" ];
        unitConfig.RequiresMountsFor = "/etc/systemd/nspawn";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          Restart = "on-failure";
          RestartSec = "30";
          ExecStart = "${pkgs.nixos-nspawn}/bin/nixos-nspawn autostart";
        };
      };
    })
    (mkIf (cfg != { }) {
      assertions = [
        {
          assertion = !config.boot.isContainer;
          message = ''
            Cannot start containers inside a container!
          '';
        }
        {
          assertion = config.networking.useNetworkd;
          message = "Only networkd is supported!";
        }
      ] ++ lib.foldlAttrs
        (acc: n: inst: acc ++ [
          {
            assertion = inst.zone != null -> (config.nixos.containers.zones != null && config.nixos.containers.zones?${inst.zone});
            message = ''
              No configuration found for zone `${inst.zone}'!
              (Invalid container: ${n})
            '';
          }
          {
            assertion = inst.zone != null -> dynamicAddrsDisabled inst;
            message = ''
              Cannot assign additional generic address-pool to a veth-pair if corresponding
              container `${n}' already uses zone `${inst.zone}'!
            '';
          }
          {
            assertion = !inst.sharedNix -> ! (elem inst.activation.strategy [ "reload" "dynamic" ]);
            message = ''
              Cannot reload a container with `sharedNix' disabled! As soon as the
              `BindReadOnly='-options change, a config activation can't be done without a reboot
              (affected: ${n})!
            '';
          }
          {
            assertion = (inst.zone != null && inst.network != null) -> (inst.network.v4.static.hostAddresses ++ inst.network.v6.static.hostAddresses) == [ ];
            message = ''
              Container ${n} is in zone ${inst.zone}, but also attempts to define
              it's one host-side addresses. Use the host-side addresses of the zone instead.
            '';
          }
        ]) [ ]
        cfg;

      # In order for systemd-nspawn to know the container's configuration, write a JSON file in etc
      # Instead of creating a drv for each json file, write them all in one runCommand.
      environment.etc."nixos-nspawn/declarative.d".source =
        let
          writers = lib.foldlAttrs
            (acc: name: containerConfig: acc + ''
              # START ${name}
              cat > '${name}.json' << 'EOF'
              ${shared.jsonContent containerConfig}
              EOF
              # END ${name}
            '')
            ""
            cfg;
        in
        pkgs.runCommand "delcarative-container-jsons" { } (''
          mkdir $out
          cd $out
        '' + writers);

      systemd = {
        # Ensure it's enabled otherwise systemd.network.units will be empty.
        network.enable = true;

        network.networks =
          lib.foldlAttrs
            (acc: name: config: acc // lib.optionalAttrs (config.network != null && config.zone == null) {
              "20-${ifacePrefix "veth"}-${name}" = {
                matchConfig = mkMatchCfg "veth" name;
                address = config.network.v4.addrPool
                # TODO Shouldn't be needed with ipv6Prefix Assign = true;
                ++ config.network.v6.addrPool
                ++ optionals (config.network.v4.static.hostAddresses != null)
                  config.network.v4.static.hostAddresses
                ++ optionals (config.network.v6.static.hostAddresses != null)
                  config.network.v6.static.hostAddresses;
                networkConfig = mkNetworkCfg (config.network.v4.addrPool != [ ]) {
                  v4Nat = config.network.v4.nat;
                  v6Nat = config.network.v6.nat;
                };
                ipv6Prefixes = map (p: { Prefix = p; }) config.network.v6.addrPool;
              };
            })
            { }
            cfg
          // lib.foldlAttrs
            (acc: name: zone: acc // {
              "20-${ifacePrefix "zone"}-${name}" = {
                matchConfig = mkMatchCfg "zone" name;
                address = zone.v4.addrPool
                # TODO Shouldn't be needed with ipv6Prefix Assign = true;
                ++ zone.v6.addrPool
                ++ zone.hostAddresses;
                networkConfig = mkNetworkCfg true {
                  v4Nat = zone.v4.nat;
                  v6Nat = zone.v6.nat;
                };
                ipv6Prefixes = map (p: { Prefix = p; }) zone.v6.addrPool;
              };
            })
            { }
            config.nixos.containers.zones;

        tmpfiles.rules = [
          "d /nix/var/nix/profiles/per-nspawn 0755 root root"
        ];
        nspawn = lib.mapAttrs (lib.const mkContainer) images;
        targets.machines.wants = map (x: "systemd-nspawn@${x}.service") (attrNames (
          lib.filterAttrs (n: v: v.activation.autoStart) cfg
        ));
        services = lib.flip lib.mapAttrs' cfg (container: { activation, timeoutStartSec, credentials, ... }@containerConfig:
          lib.nameValuePair "systemd-nspawn@${container}" {
            overrideStrategy = "asDropin";

            # Force cgroupv2
            # https://github.com/NixOS/nixpkgs/pull/198526
            environment.SYSTEMD_NSPAWN_UNIFIED_HIERARCHY = "1";

            preStart = mkBefore ''
              if [ ! -d /var/lib/machines/${container} ]; then
                mkdir -p /var/lib/machines/${container}/{etc,var,nix/var/nix}
                touch /var/lib/machines/${container}/etc/{os-release,machine-id}
              fi
            '';

            restartTriggers = lib.optionals (activation.strategy != "none") [
              (shared.jsonContent containerConfig)
              # Some support for out of band changes
              (builtins.toJSON [
                config.systemd.nspawn.${container}.filesConfig
                config.systemd.nspawn.${container}.networkConfig
              ])
            ];

            restartIfChanged = activation.strategy != "none";

            serviceConfig = {
              TimeoutStartSec = timeoutStartSec;
              ExecStart =
                let
                  credsArgv = lib.concatMapStringsSep " " ({ id, path }: "'--load-credential=${id}:${path}'") credentials;
                in
                optionals (credentials != [ ]) [
                  ""
                  "${config.systemd.package}/bin/systemd-nspawn ${credsArgv} --quiet --keep-unit --boot --network-veth --settings=override --machine=%i"
                ];
              ExecReload = if activation.reloadScript != null then activation.reloadScript else
              pkgs.writeShellScript "activate" ''
                pid=$(${config.systemd.package}/bin/machinectl show '${container}' --value --property Leader)
                ${pkgs.util-linux}/bin/nsenter -t "$pid" -a \
                  -- ${images.${container}.container.config.system.build.toplevel}/bin/switch-to-configuration test
              '';
            };
          }
        );
      };
    })
  ];
}
