# The per-container configuration installed onto the hypervisor.
# This structure means we only need to iterate config.nixos.containers.instances once.
{
  pkgs,
  lib,
  hostConfig,
  shared,
}:
name: container:
let
  inherit (lib) mkIf mkDefault;
  inherit (container) activation timeoutStartSec credentials;
  idmap = lib.optionalString container.userNamespacing ":rootidmap";
  toplevel = container.system-config.config.system.build.toplevel;
  credsArgv = lib.concatMapStringsSep " " (
    { id, path }: "'--load-credential=${id}:${path}'"
  ) credentials;

  mkForwardPorts = map (
    {
      containerPort ? null,
      hostPort,
      protocol,
    }:
    let
      host = toString hostPort;
      container = if containerPort == null then host else toString containerPort;
    in
    "${protocol}:${host}:${container}"
  );
in
{
  assertions = [
    {
      assertion =
        container.sharedNix
        || !(lib.elem container.activation.strategy [
          "reload"
          "dynamic"
        ]);
      message = ''
        Cannot reload container `${name}' with `sharedNix' disabled! As soon as the
        `BindReadOnly='-options change, a config activation can't be done without a reboot.
      '';
    }
    {
      assertion = container.zone == null || container.hostNetworkConfig == null;
      message = ''
        hostNetworkConfig and zone are mututally exclusive on container `${name}'.
        You may want to configure `nixos.containers.zones.${container.zone}' instead.
      '';
    }
  ];

  systemd = {
    targets.machines.wants = lib.optionals activation.autoStart [ "systemd-nspawn@${name}.service" ];

    services."systemd-nspawn@${name}" = {
      overrideStrategy = "asDropin";

      # Force cgroupv2
      # https://github.com/NixOS/nixpkgs/pull/198526
      environment.SYSTEMD_NSPAWN_UNIFIED_HIERARCHY = "1";

      preStart = lib.mkBefore ''
        if [ ! -d /var/lib/machines/${name} ]; then
          mkdir -p /var/lib/machines/${name}/{etc,var,nix/var/nix}
          touch /var/lib/machines/${name}/etc/{os-release,machine-id}
        fi
      '';

      restartTriggers = lib.optionals (activation.strategy != "none") [
        (shared.jsonContent container)
        # Some support for out of band changes
        (builtins.toJSON [
          hostConfig.systemd.nspawn.${name}.filesConfig
          hostConfig.systemd.nspawn.${name}.networkConfig
        ])
      ];

      restartIfChanged = activation.strategy != "none";

      serviceConfig = {
        TimeoutStartSec = timeoutStartSec;
        # Only override the default ExecStart if credentials are defined.
        # Other than credsArgv, the command line is unchanged.
        ExecStart = lib.optionals (credentials != [ ]) [
          ""
          "${hostConfig.systemd.package}/bin/systemd-nspawn ${credsArgv} --quiet --keep-unit --boot --network-veth --settings=override --machine=%i"
        ];
        ExecReload =
          if activation.reloadScript != null then
            activation.reloadScript
          else
            ''
              ${hostConfig.systemd.package}/bin/systemd-run --quiet --machine=%i --collect --no-ask-password --pipe --service-type=exec ${toplevel}/bin/switch-to-configuration test
            '';
      };
    };

    nspawn."${name}" = lib.mkMerge [
      {
        execConfig = {
          NotifyReady = true;
          Boot = false;
          Parameters = "${toplevel}/init";
          Ephemeral = shared.yesNo container.ephemeral;
          SystemCallFilter = lib.mkIf (container.systemCallFilter != null) container.systemCallFilter;
          KillSignal = "SIGRTMIN+3";
          PrivateUsers = mkDefault (if container.userNamespacing then "pick" else "no");
          LinkJournal = mkDefault (if container.ephemeral then "auto" else "guest");
        };
        filesConfig = {
          PrivateUsersOwnership = mkDefault (if container.userNamespacing then "auto" else "chown");
          Bind = container.bindMounts;
        };
        networkConfig = lib.mkMerge [
          {
            Bridge = mkIf (container.bridge != null) container.bridge;
            Zone = mkIf (container.zone != null) container.zone;
            Port = mkForwardPorts container.forwardPorts;
          }
          (mkIf (container.zone != null || container.hostNetworkConfig != null) {
            Private = true;
            VirtualEthernet = "yes";
          })
        ];
      }
      (mkIf container.sharedNix {
        filesConfig.BindReadOnly = [
          "/nix/store:/nix/store${idmap}"
          "/nix/var/nix/profiles:/nix/var/nix/profiles${idmap}"
        ];
      })
      (mkIf (container.sharedNix && container.mountDaemonSocket) {
        filesConfig.BindReadOnly = [ "/nix/var/nix/db:/nix/var/nix/db${idmap}" ];
        filesConfig.Bind = [ "/nix/var/nix/daemon-socket:/nix/var/nix/daemon-socket${idmap}" ];
      })
      (mkIf (!container.sharedNix) {
        # Bind (read-only) all the store paths required to run the container
        extraDrvConfig =
          let
            info = pkgs.closureInfo {
              rootPaths = [ toplevel ];
            };
          in
          pkgs.runCommand "bindmounts.nspawn" { } ''
            echo "[Files]" > $out

            cat ${info}/store-paths | while read line
            do
              echo "BindReadOnly=$line:$line${idmap}" >> $out
            done
          '';
      })
    ];

    network.networks = lib.mkIf (container.hostNetworkConfig != null && container.zone == null) (
      shared.mkNetwork name "veth" container.hostNetworkConfig
    );
  };
}
