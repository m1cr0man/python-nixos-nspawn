rec {
  containerOptions = import ./containers-next/container-options.nix;

  containerProfileModule = import ./containers-next/container-profile.nix;

  containerAssertions = { containerConfig, lib, ... }: [
    {
      assertion = containerConfig.sharedNix;
      message = "Experimental 'sharedNix'-feature isn't supported for imperative containers!";
    }
    {
      assertion = containerConfig.activation.strategy != "dynamic";
      message = "'dynamic' is currently not supported for imperative containers!";
    }
  ];

  mkContainer =
    { nixpkgs
    , name
    , system
    , pkgs ? (import "${nixpkgs}/pkgs/top-level/default.nix" { localSystem.system = system; })
    , modules ? [ ]
    }:
    let
      # Generate the container filesystem like any regular NixOS system.
      container = import "${nixpkgs}/nixos/lib/eval-config.nix"
        {
          inherit pkgs system;
          inherit (pkgs) lib;
          modules = [
            containerProfileModule
            ({ config, pkgs, lib, ... }: {
              options.nixosContainer =
                containerOptions
                  { inherit pkgs lib; declarative = false; };

              config = {
                assertions = containerAssertions
                  { inherit lib; containerConfig = config.nixosContainer; };

                networking.hostName = name;
              };
            })
          ] ++ modules;
        };
      # Generate a config for a virtual host/hypervisor system too.
      # This allows us to generate the necessary Systemd config files
      # for the container in Nix. They are put in place by the Python
      # code after evaluation.
      host = import "${nixpkgs}/nixos/lib/eval-config.nix"
        {
          inherit pkgs system;
          inherit (pkgs) lib;
          modules = [
            ./containers-next/hypervisor.nix
            ({ config, pkgs, lib, ... }: {
              # Add the nixosContainer option to this system so that
              # the imperative container's configuration can be parsed.
              options = {
                nixosContainer =
                  containerOptions
                    { inherit pkgs lib; declarative = true; };
              };
            })
            ({ config, lib, ... }: {
              # A bit of a hack.. Use the imperative container's config as an
              # imperative container. This will fill in the required parts of
              # the module configuration to generate the Systemd units.
              nixos.containers.instances."${name}" = config.nixosContainer // {
                # Since we already have the container's configuration evaluated above,
                # reuse it here. This is essential for the correct init path in the nspawn unit.
                system-config = container;
              };
            })
          ] ++ modules;
        };
    in
    pkgs.buildEnv {
      inherit name;
      # We need to add a JSON copy of the nixosContainer options so that
      # nixos_nspawn can generate the relevant systemd units.
      paths = [
        host.config.environment.etc."systemd/nspawn".source
        # (pkgs.writeTextDir "host" (builtins.toJSON host.config.nixos.containers.instances.example))
        # host.config.environment.etc."systemd/network/20-ve-${name}".source
        container.config.system.build.toplevel
        (pkgs.writeTextDir "data" (builtins.toJSON container.config.nixosContainer))
      ];
    };
}
