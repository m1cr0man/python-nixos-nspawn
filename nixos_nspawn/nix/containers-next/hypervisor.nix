{ pkgs, lib, config, ... }:

with lib;

let
  cfg = config.nixos.containers.instances;

  shared = import ./shared.nix { inherit lib; };

  inherit (shared) ifacePrefix mkNetworkingOpts;

  yesNo = x: if x then "yes" else "no";

  dynamicAddrsDisabled = inst:
    inst.network == null || inst.network.v4.addrPool == [ ] && inst.network.v6.addrPool == [ ];

  mkRadvdSection = type: name: v6Pool:
    assert elem type [ "veth" "zone" ];
    ''
      interface ${ifacePrefix type}-${name} {
        AdvSendAdvert on;
        ${flip concatMapStrings v6Pool (x: ''
          prefix ${x} {
            AdvOnLink on;
            AdvAutonomous on;
          };
        '')}
      };
    '';

  zoneCfg = config.nixos.containers.zones;

  interfaces.containers = attrNames cfg;
  interfaces.zones = attrNames config.nixos.containers.zones;
  radvd = {
    enable = with interfaces; containers != [ ] || zones != [ ];
    config = concatStringsSep "\n" [
      (concatMapStrings
        (x: mkRadvdSection "veth" x cfg.${x}.network.v6.addrPool)
        (filter
          (n: cfg.${n}.network != null && cfg.${n}.zone == null)
          (attrNames cfg)))
      (concatMapStrings
        (x: mkRadvdSection "zone" x config.nixos.containers.zones.${x}.v6.addrPool)
        (attrNames config.nixos.containers.zones))
    ];
  };

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
    IPForward = "yes";
    LLDP = "yes";
    EmitLLDP = "customer-bridge";
    IPv6AcceptRA = "no";
  };

  recUpdate3 = a: b: c:
    recursiveUpdate a (recursiveUpdate b c);

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
    let inherit (cfg) container config; in
    mkMerge [
      {
        execConfig = {
          Boot = false;
          Parameters = "${container.config.system.build.toplevel}/init";
          Ephemeral = yesNo config.ephemeral;
          KillSignal = "SIGRTMIN+3";
          PrivateUsers = mkDefault "yes";
          LinkJournal = mkDefault (if config.ephemeral then "auto" else "guest");
          X-ActivationStrategy = config.activation.strategy;
        };
        filesConfig = mkMerge [
          {
            PrivateUsersOwnership = mkDefault "auto";
            Bind = config.bindMounts;
          }
          (mkIf config.sharedNix {
            BindReadOnly = [
              "/nix/store"
              "/nix/var/nix/profiles"
              "/nix/var/nix/profiles/per-nspawn"
            ] ++ optional config.mountDaemonSocket "/nix/var/nix/db";
          })
          (mkIf (config.sharedNix && config.mountDaemonSocket) {
            Bind = [ "/nix/var/nix/daemon-socket" ];
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
                echo "BindReadOnly=$line" >> $out
              done
            '';
      })
    ];

  images = mapAttrs mkImage cfg;
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
        options = import ./container-options.nix { inherit pkgs lib name config; declarative = true; };
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
    {
      systemd.services.nixos-nspawn-autostart = mkIf (config.nixos.containers.enableAutostartService) {
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
    }
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
      ] ++ foldlAttrs
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

      services = { inherit radvd; };

      systemd = {
        # Ensure it's enabled otherwise systemd.network.units will be empty.
        network.enable = true;

        network.networks =
          foldlAttrs
            (acc: name: config: acc // optionalAttrs (config.network != null && config.zone == null) {
              "20-${ifacePrefix "veth"}-${name}" = {
                matchConfig = mkMatchCfg "veth" name;
                address = config.network.v4.addrPool
                ++ config.network.v6.addrPool
                ++ optionals (config.network.v4.static.hostAddresses != null)
                  config.network.v4.static.hostAddresses
                ++ optionals (config.network.v6.static.hostAddresses != null)
                  config.network.v6.static.hostAddresses;
                networkConfig = mkNetworkCfg (config.network.v4.addrPool != [ ]) {
                  v4Nat = config.network.v4.nat;
                  v6Nat = config.network.v6.nat;
                };
              };
            })
            { }
            cfg
          // foldlAttrs
            (acc: name: zone: acc // {
              "20-${ifacePrefix "zone"}-${name}" = {
                matchConfig = mkMatchCfg "zone" name;
                address = zone.v4.addrPool
                ++ zone.v6.addrPool
                ++ zone.hostAddresses;
                networkConfig = mkNetworkCfg true {
                  v4Nat = zone.v4.nat;
                  v6Nat = zone.v6.nat;
                };
              };
            })
            { }
            config.nixos.containers.zones;

        nspawn = mapAttrs (const mkContainer) images;
        targets.machines.wants = map (x: "systemd-nspawn@${x}.service") (attrNames (
          filterAttrs (n: v: v.activation.autoStart) cfg
        ));
        services = flip mapAttrs' cfg (container: { activation, timeoutStartSec, credentials, ... }:
          nameValuePair "systemd-nspawn@${container}" {
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

            serviceConfig = {
              TimeoutStartSec = timeoutStartSec;
              X-ActivationStrategy = activation.strategy;
              ExecStart =
                let
                  credsArgv = lib.concatMapStringsSep " " ({ id, path }: "'--load-credential=${id}:${path}'") credentials;
                in
                optionals (credentials != [ ]) [
                  ""
                  "${config.systemd.package}/bin/systemd-nspawn ${credsArgv} --quiet --keep-unit --boot --network-veth --settings=override --machine=%i"
                ];
              ExecReload =
                let
                  reloadScript =
                    if activation.reloadScript != null then activation.reloadScript
                    else
                      pkgs.writeShellScript "activate" ''
                        pid=$(${config.systemd.package}/bin/machinectl show '${container}' --value --property Leader)
                        ${pkgs.util-linux}/bin/nsenter -t "$pid" -m -u -U -i -n -p \
                          -- ${images.${container}.container.config.system.build.toplevel}/bin/switch-to-configuration test
                      '';
                in
                mkIf (elem activation.strategy [ "reload" "dynamic" ]) (builtins.toString reloadScript);
            };
          }
        );
      };
    })
  ];
}
