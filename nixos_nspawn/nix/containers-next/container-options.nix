{ pkgs, lib, declarative ? true, ... }:
let
  shared = import ./shared.nix { inherit lib; };

  inherit (shared) mkNetworkingOpts;

  inherit (lib) mkIf mkOption mkEnableOption mkMerge types literalExpression;

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
          description = lib.mdDoc ''
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

          description = lib.mdDoc ''
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
  sharedNix = mkOption {
    default = true;
    type = types.bool;
    description = lib.mdDoc ''
      ::: {.warning}
        Experimental setting! Expect things to break!
      :::

      With this option **disabled**, only the needed store-paths will
      be mounted into the container rather than the entire store.
    '';
  };

  mountDaemonSocket = mkEnableOption (lib.mdDoc "daemon-socket in the container");

  ephemeral = mkEnableOption "ephemeral container" // {
    description = lib.mdDoc ''
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
    description = lib.mdDoc ''
      Name of the networking bridge to connect the container to.
    '';
  };

  zone = mkOption {
    type = types.nullOr types.str;
    default = null;
    description = lib.mdDoc ''
      Name of the networking zone defined by {manpage}`systemd.nspawn(5)`.
    '';
  };

  credentials = mkOption {
    type = types.listOf (types.submodule {
      options = {
        id = mkOption {
          type = types.str;
          description = lib.mdDoc ''
            ID of the credential under which the credential can be referenced by services
            inside the container.
          '';
        };
        path = mkOption {
          type = types.str;
          description = lib.mdDoc ''
            Path or ID of the credential passed to the container.
          '';
        };
      };
    });
    apply = lib.concatMapStringsSep " " ({ id, path }: "--load-credential=${id}:${path}");
    default = [ ];
    description = lib.mdDoc ''
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
      description = lib.mdDoc ''
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
      description = lib.mdDoc ''
        Script to run when a container is supposed to be reloaded.
      '';
    };
  };

  network = mkOption {
    type = types.nullOr (types.submodule networkSubmodule);
    default = null;
    description = lib.mdDoc ''
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
          description = lib.mdDoc ''
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

    apply = map
      ({ containerPort ? null, hostPort, protocol }:
        let
          host = toString hostPort;
          container = if containerPort == null then host else toString containerPort;
        in
        "${protocol}:${host}:${container}");

    description = lib.mdDoc ''
      Define port-forwarding from a container to host. See `--port` section
      of {manpage}`systemd-nspawn(5)` for further information.
    '';
  };

} // (if declarative then {
  nixpkgs = mkOption {
    default = pkgs.path;
    type = types.path;
    description = lib.mdDoc ''
      Path to the `nixpkgs`-checkout or channel to use for the container.
    '';
  };

  system-config = mkOption {
    description = lib.mdDoc ''
      NixOS configuration for the container. See {manpage}`configuration.nix(5)` for available options.
    '';
    default = { };
    # TODO figure out why the custom type breaks recursive evaluation
    # for the imperative host nspawn unit
    type = types.attrs;
  };

  timeoutStartSec = mkOption {
    type = types.str;
    default = "90s";
    description = lib.mdDoc ''
      Timeout for the startup of the container. Corresponds to `DefaultTimeoutStartSec`
      of {manpage}`systemd.system(5)`.
    '';
  };
} else { })
