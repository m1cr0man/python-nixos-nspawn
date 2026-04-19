{
  pkgs,
  lib,
  name,
  declarative ? true,
  config ? null,
  hostConfig ? null,
  ...
}:
let
  shared = import ./shared.nix { inherit lib; };

  inherit (lib)
    mkIf
    mkOption
    mkOptionType
    mkEnableOption
    mkMerge
    types
    literalExpression
    ;
in
{
  declarative = mkOption {
    default = declarative;
    type = types.bool;
    description = ''
      Indicates whether this container is declarative or imperative.
    '';
  };

  sharedNix = mkOption {
    default = true;
    type = types.bool;
    description = ''
      ::: {.warning}
        Experimental setting! Expect things to break!
      :::

      With this option **disabled**, only the needed store-paths will
      be mounted into the container rather than the entire store.
    '';
  };

  mountDaemonSocket = mkEnableOption ("daemon-socket in the container");

  ephemeral = mkEnableOption "ephemeral container" // {
    description = ''
      `ephemeral` means that the container's rootfs will be wiped
      before every startup. See {manpage}`systemd.nspawn(5)` for further context.
    '';
  };

  userNamespacing = mkOption {
    default = false;
    type = types.bool;
    description = ''
      Whether to use user/group namespacing. This will also enable idmapping on core mounts.
      You may want to disable this if you run into boot issues related to idmap bind mounts.
    '';
  };

  systemCallFilter = mkOption {
    default = null;
    type = types.nullOr types.str;
    description = ''
      Whether to filter system calls for the container.
      Corresponds to `SystemCallFilter` of {manpage}`systemd.exec(5)`.
    '';
  };

  bindMounts = mkOption {
    default = [ ];
    type = types.listOf types.str;
    description = ''
      Extra paths to bind into the container.
      These take the form of "hostPath:containerPath[:options]".
    '';
  };

  bridge = mkOption {
    type = types.nullOr types.str;
    default = null;
    description = ''
      Name of the networking bridge to connect the container to.
    '';
  };

  zone = mkOption {
    type = types.nullOr types.str;
    default = null;
    description = ''
      Name of the networking zone defined by {manpage}`systemd.nspawn(5)`.
    '';
  };

  credentials = mkOption {
    type = types.listOf (
      types.submodule {
        options = {
          id = mkOption {
            type = types.str;
            description = ''
              ID of the credential under which the credential can be referenced by services
              inside the container.
            '';
          };
          path = mkOption {
            type = types.str;
            description = ''
              Path or ID of the credential passed to the container.
            '';
          };
        };
      }
    );
    default = [ ];
    description = ''
      Credentials using the `LoadCredential=`-feature from
      {manpage}`systemd.exec(5)`. These will be passed to the container's service-manager
      and can be used in a service inside a container like

      ```nix
      {
        systemd.services."service-name".serviceConfig.LoadCredential = "foo:foo";
      }
      ```

      where `foo` is the `id` of the credential passed to the container.

      See also {manpage}`systemd-nspawn(1)`.
    '';
  };

  activation = {
    strategy = mkOption {
      type = types.enum [
        "none"
        "reload"
        "restart"
        "dynamic"
      ];
      default = if declarative then "dynamic" else "restart";
      description = ''
        Decide whether to **restart** or **reload**
        the container during activation.

        **dynamic** checks whether the `.nspawn`-unit
        has changed (apart from the init-script) and if that's the case, it will be
        restarted, otherwise a reload will happen.
      '';
    };

    reloadScript = mkOption {
      default = null;
      type = types.nullOr types.path;
      description = ''
        Script to run when a container is supposed to be reloaded.
      '';
    };

    autoStart = (mkEnableOption "starting the container on hypervisor boot") // {
      default = true;
    };
  };

  hostNetworkConfig = mkOption {
    type = types.nullOr types.attrs;
    default = null;
    description = ''
      Extra options to pass to the configuration for the hypervisor's network interface.
      This only applies to containers using private networking - that is, they are not
      assigned to a bridge or zone.

      See {option}`systemd.network.networks` for a full list of options.

      If null, the defaults defined by systemd are used. This results in a
      network with a randomly assigned IPv4 subnet and an IPv6 link local address.
      IPv4 NAT will be enabled and will grant the container internet access.

      Using this is preferred over adding options via systemd.network.networks as
      care has been taken to preserve the default host0 configuration from pkgs.systemd.
    '';
  };

  containerNetworkConfig = mkOption {
    type = types.nullOr types.attrs;
    default = null;
    description = ''
      Extra options to pass to the configuration for the container's host0 interface.

      See {option}`systemd.network.networks` for a full list of options.

      If null, the defaults defined by systemd are used. This results in a
      network with DHCP, link local addresses and LLDP enabled which is reachable from
      the host network.

      Using this is preferred over adding options via systemd.network.networks.host0 as
      care has been taken to preserve the default host0 configuration from pkgs.systemd.
    '';
  };

  forwardPorts = mkOption {
    default = [ ];
    example = literalExpression ''
      [
        { containerPort = 80; hostPort = 8080; protocol = "tcp"; }
      ]
    '';

    type = types.listOf (
      types.submodule {
        options = {
          containerPort = mkOption {
            type = types.nullOr types.port;
            default = null;
            description = ''
              Port to forward on the container-side. If `null`, the
              [](#opt-nixos.containers.instances._name_.forwardPorts._.hostPort)-option
              will be used.
            '';
          };

          hostPort = mkOption {
            type = types.port;
            description = ''
              Source port on the host-side.
            '';
          };

          protocol = mkOption {
            default = "tcp";
            type = types.enum [
              "udp"
              "tcp"
            ];
            description = ''
              Protocol specifier for the port-forward between host and container.
            '';
          };
        };
      }
    );

    description = ''
      Define port-forwarding from a container to host. See `--port` section
      of {manpage}`systemd-nspawn(5)` for further information.
    '';
  };

  timeoutStartSec = mkOption {
    type = types.str;
    default = "90s";
    description = ''
      Timeout for the startup of the container. Corresponds to `DefaultTimeoutStartSec`
      of {manpage}`systemd.system(5)`.
    '';
  };

}
// (
  if declarative then
    {
      nixpkgs = mkOption {
        default = null;
        type = types.nullOr types.path;
        description = ''
          Path to the `nixpkgs`-checkout or channel to use for the container.
          If not provided, the current nixpkgs eval is used.

          Only available for declarative containers.
        '';
      };

      config = mkOption {
        description = ''
          NixOS configuration for the container.
          See {manpage}`configuration.nix(5)` for available options.

          Only available for declarative containers. Imperative containers can
          be configured as usual without this option.
        '';
        default = { };
        type = mkOptionType {
          name = "NixOS configuration";
          # Instead of merging the attrs at this stage, map out each
          # attrset into an import and let the eval-config merge them later.
          merge = lib.const (
            map (x: rec {
              imports = [ x.value ];
              key = _file;
              _file = x.file;
            })
          );
        };
        apply =
          let
            system = pkgs.stdenv.hostPlatform.system;
            # Evaluate user-specified nixpkgs if necessary
            pkgs' =
              if config.nixpkgs == null then
                pkgs
              else
                import config.nixpkgs {
                  inherit system;
                  inherit (pkgs) config;
                };
          in
          cfgs:
          import "${pkgs'.path}/nixos/lib/eval-config.nix" {
            inherit system;
            inherit (pkgs') lib;
            pkgs = pkgs';
            modules = cfgs ++ [
              ./container-profile.nix
              (
                { pkgs, ... }:
                {
                  networking.hostName = lib.mkDefault name;
                  system.stateVersion = mkIf (hostConfig != null) (lib.mkDefault hostConfig.system.stateVersion);
                  systemd.network.networks = mkIf (config.containerNetworkConfig != null) (
                    shared.mkContainerNetwork config.containerNetworkConfig
                  );
                }
              )
            ];
            prefix = [
              "nixos"
              "containers"
              "instances"
              name
              "config"
            ];
          };
      };
    }
  else
    { }
)
