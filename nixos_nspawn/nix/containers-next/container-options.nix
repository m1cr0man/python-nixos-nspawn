{ pkgs, lib, declarative ? true }:
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
          description = ''
            Address of the container on the host-side, i.e. the
            subnet and address assigned to <literal>ve-&lt;name&gt;</literal>.
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
            subnet and address assigned to the <literal>host0</literal>-interface.
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
    description = ''
      <warning>
        <para>Experimental setting! Expect things to break!</para>
      </warning>

      With this option <emphasis>disabled</emphasis>, only the needed store-paths will
      be mounted into the container rather than the entire store.
    '';
  };

  ephemeral = mkEnableOption "ephemeral container" // {
    description = ''
      <literal>ephemeral</literal> means that the container's rootfs will be wiped
      before every startup. See <citerefentry><refentrytitle>systemd.nspawn</refentrytitle>
      <manvolnum>5</manvolnum></citerefentry> for further context.
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
      Name of the networking zone defined by <citerefentry>
      <refentrytitle>systemd.nspawn</refentrytitle><manvolnum>5</manvolnum></citerefentry>.
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
      Credentials using the <literal>LoadCredential=</literal>-feature from
      <citerefentry><refentrytitle>systemd.exec</refentrytitle><manvolnum>5</manvolnum>
      </citerefentry>. These will be passed to the container's service-manager
      and can be used in a service inside a container like

      <programlisting>
      {
        <xref linkend="opt-systemd.services._name_.serviceConfig" />.LoadCredential = "foo:foo";
      }
      </programlisting>

      where <literal>foo</literal> is the
      <xref linkend="opt-nixos.containers.instances._name_.credentials._.id" /> of the
      credential passed to the container.

      See also <citerefentry><refentrytitle>systemd-nspawn</refentrytitle>
      <manvolnum>1</manvolnum></citerefentry>.
    '';
  };

  activation = {
    strategy = mkOption {
      type = types.enum [ "none" "reload" "restart" "dynamic" ];
      default = if declarative then "dynamic" else "restart";
      description = ''
        Decide whether to <emphasis>restart</emphasis> or <emphasis>reload</emphasis>
        the container during activation.

        <literal>dynamic</literal> checks whether the <filename>.nspawn</filename>-unit
        has changed (apart from the init-script) and if that's the case, it will be
        rebooted, otherwise a restart will happen.
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
      <literal>veth</literal>-pair is created. It's possible to configure a dynamically
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
            Port to forward on the container-side. If <literal>null</literal>, the
            <xref linkend="opt-nixos.containers.instances._name_.forwardPorts._.hostPort" />-option
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

    description = ''
      Define port-forwarding from a container to host. See <literal>--port</literal>-section
      of <citerefentry><refentrytitle>systemd-nspawn</refentrytitle><manvolnum>1</manvolnum>
      </citerefentry> for further information.
    '';
  };

} // (if declarative then {
  nixpkgs = mkOption {
    default = pkgs.path;
    type = types.path;
    description = ''
      Path to the `nixpkgs`-checkout or channel to use for the container.
    '';
  };

  system-config = mkOption {
    description = ''
      NixOS configuration for the container. See <citerefentry>
      <refentrytitle>configuration.nix</refentrytitle><manvolnum>5</manvolnum>
      </citerefentry> for available options.
    '';
    default = { };
    type = lib.mkOptionType {
      name = "NixOS configuration";
      merge = lib.const (map (x: rec { imports = [ x.value ]; key = _file; _file = x.file; }));
    };
  };
} else { })
