{ pkgs, lib, name, declarative ? true, config ? null, ... }:
let
  shared = import ./shared.nix { inherit lib; };

  inherit (shared) mkNetworkingOpts;

  inherit (lib) mkIf mkOption mkOptionType mkEnableOption mkMerge types literalExpression;

  recUpdate3 = a: b: c: lib.recursiveUpdate a (lib.recursiveUpdate b c);

  mkStaticNetOptions = v:
    assert lib.elem v [ 4 6 ]; {
      "v${toString v}".static = {
        hostAddresses = mkOption {
          default = [ ];
          type = types.listOf types.str;
          example = literalExpression (
            if v == 4 then ''[ "10.151.1.1/24" ]''
            else ''[ "fd23::/64" ]''
          );
          description = ''
            Address of the container on the host-side, i.e. the
            subnet and address assigned to `ve-<name>`.
          '';
        };
        containerPool = mkOption {
          default = [ ];
          type = types.listOf types.str;
          example = literalExpression (
            if v == 4 then ''[ "10.151.1.2/24" ]''
            else ''[ "fd23::2/64" ]''
          );

          description = ''
            Addresses to be assigned to the container, i.e. the
            subnet and address assigned to the `host0`-interface.
          '';
        };
      };
    };

  networkSubmodule = {
    options = recUpdate3
      (mkNetworkingOpts "veth")
      (mkStaticNetOptions 4)
      (mkStaticNetOptions 6);
  };
in
{
  declarative = mkOption {
    default = declarative;
    readOnly = true;
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

  bindMounts = mkOption {
    default = [ ];
    type = types.listOf types.str;
    description = ''
      Extra paths to bind into the container.
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
    type = types.listOf (types.submodule {
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
    });
    apply = lib.concatMapStringsSep " " ({ id, path }: "--load-credential=${id}:${path}");
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
      type = types.enum [ "none" "reload" "restart" "dynamic" ];
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
  };

  network = mkOption {
    type = types.nullOr (types.submodule networkSubmodule);
    default = null;
    description = ''
      Networking options for a single container. With this option used, a
      `veth`-pair is created. It's possible to configure a dynamically
      managed network with private IPv4 and ULA IPv6 the same way like zones.
      Additionally, it's possible to statically assign addresses to a container here.
    '';
  };

  forwardPorts = mkOption {
    default = [ ];
    example = literalExpression
      ''
        [
          { containerPort = 80; hostPort = 8080; protocol = "tcp"; }
        ]
      '';

    type = types.listOf (types.submodule {
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
          type = types.enum [ "udp" "tcp" ];
          description = ''
            Protocol specifier for the port-forward between host and container.
          '';
        };
      };
    });

    description = ''
      Define port-forwarding from a container to host. See `--port` section
      of {manpage}`systemd-nspawn(5)` for further information.
    '';
  };

} // (if declarative then {
  nixpkgs = mkOption {
    default = pkgs.path;
    defaultText = "pkgs.path";
    type = types.path;
    description = ''
      Path to the `nixpkgs`-checkout or channel to use for the container.
    '';
  };

  system-config = mkOption {
    description = ''
      NixOS configuration for the container. See {manpage}`configuration.nix(5)` for available options.
    '';
    default = { };
    type = mkOptionType {
      name = "NixOS configuration";
      # Instead of merging the attrs at this stage, map out each
      # attrset into an import and let the eval-config merge them later.
      merge = lib.const (map (x: rec { imports = [ x.value ]; key = _file; _file = x.file; }));
    };
    apply = let
      system = pkgs.stdenv.hostPlatform.system;
      nixpkgs = config.nixpkgs;
      # Avoid needless import of nixpkgs
      pkgs' = if nixpkgs == pkgs.path then pkgs else import nixpkgs {
        inherit system;
        inherit (pkgs) config;
      };
    in cfgs: import "${nixpkgs}/nixos/lib/eval-config.nix" {
      inherit system;
      inherit (pkgs') lib;
      pkgs = pkgs';
      modules = cfgs ++ [
        ./container-profile.nix
        ({ pkgs, ... }: {
          networking.hostName = lib.mkDefault name;
          systemd.network.networks."20-host0" = mkIf (config.network != null) {
            address = with config.network; v4.static.containerPool ++ v6.static.containerPool;
          };
        })
      ];
      prefix = [ "nixos" "containers" "instances" name "system-config" ];
    };
  };

  timeoutStartSec = mkOption {
    type = types.str;
    default = "90s";
    description = ''
      Timeout for the startup of the container. Corresponds to `DefaultTimeoutStartSec`
      of {manpage}`systemd.system(5)`.
    '';
  };
} else { })
