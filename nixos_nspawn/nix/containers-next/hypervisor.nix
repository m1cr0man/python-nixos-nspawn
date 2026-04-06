{ pkgs, lib, config, ... }:

let
  hostConfig = config;
  cfg = config.nixos.containers.instances;

  shared = import ./shared.nix { inherit lib; };
  inherit (lib) mkIf;

  # Unfortunately, we can't map over the instances in the root of config.
  # It causes infinite recursion.
  # We have to construct the individual elements and combine them later.
  containerBuilder = import ./container-builder.nix { inherit pkgs lib hostConfig shared; };
  containerConfigs = lib.mapAttrs containerBuilder cfg;
  assertions = lib.foldlAttrs (acc: name: container: acc ++ container.assertions) [] containerConfigs;
  systemdConfigs = lib.mapAttrsToList (name: container: container.systemd) containerConfigs;
in
{
  options.nixos.containers = {
    instances = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, config, ... }:
          {
            options = import ./container-options.nix {
              inherit
                pkgs
                lib
                name
                config
                hostConfig
                ;
              declarative = true;
            };
          }
        )
      );

      description = ''
        Attribute set to define {manpage}`systemd.nspawn(5)`-managed containers. With this attribute-set,
        a network, a shared store and a NixOS configuration can be declared for each running
        container.

        The container's state is managed in `/var/lib/machines/<name>`.
        A machine can be started with the
        `systemd-nspawn@<name>.service`-unit, during runtime it can
        be accessed with {manpage}`machinectl(1)`.

        TODO is this true? I think not.

        Please note that if both [](#opt-nixos.containers.instances._name_.network)
        & [](#opt-nixos.containers.instances._name_.zone) are
        `null`, the container will use the host's network.
      '';
    };

    zones = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = shared.mkNetworkingOpts "zone";
        }
      );
      default = { };
      description = ''
        Networking zones for nspawn containers. In this mode, the host-side
        of the virtual ethernet of a machine is managed by an interface named
        `vz-<name>`.
      '';
    };

    enableAutostartService = (lib.mkEnableOption "autostarting of imperative containers") // {
      default = true;
    };
  };

  config = lib.mkMerge [
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

      assertions = assertions ++ [
        {
          assertion = !config.boot.isContainer;
          message = "Cannot start containers inside a container!";
        }
        {
          assertion = config.networking.useNetworkd;
          message = "Only networkd is supported!";
        }
      ];

      systemd = lib.mkMerge (
        systemdConfigs
        ++ [
          {
            tmpfiles.rules = [
              "d /nix/var/nix/profiles/per-nspawn 0755 root root"
            ];

            # Force systemd network to be usd
            network.enable = true;

            network.networks = lib.mapAttrs' (name: zone:
              lib.nameValuePair
              "20-${shared.ifacePrefix "zone"}-${name}"
              {
                matchConfig = shared.mkMatchCfg "zone" name;
                address = zone.v4.addrPool ++ zone.v6.addrPool ++ zone.hostAddresses;
                networkConfig = shared.mkNetworkCfg {
                  v4Nat = zone.v4.nat;
                  v6Nat = zone.v6.nat;
                };
                ipv6Prefixes = map (p: { Prefix = p; }) zone.v6.addrPool;
              }
            ) hostConfig.nixos.containers.zones;
          }
        ]
      );

      # In order for systemd-nspawn to know the container's configuration, write a JSON file in etc
      # Instead of creating a drv for each json file, write them all in one runCommand.
      environment.etc."nixos-nspawn/declarative.d".source =
        let
          writers = lib.foldlAttrs (
            acc: name: containerConfig:
            acc
            + ''
              # START ${name}
              cat > '${name}.json' << 'EOF'
              ${shared.jsonContent containerConfig}
              EOF
              # END ${name}
            ''
          ) "" cfg;
        in
        pkgs.runCommand "delcarative-container-jsons" { } (
          ''
            mkdir $out
            cd $out
          ''
          + writers
        );
    })
  ];
}
