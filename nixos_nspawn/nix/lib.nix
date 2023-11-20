rec {

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
      containerOptions = import ./containers-next/container-options.nix {
        inherit pkgs name;
        inherit (pkgs) lib;
        declarative = false;
      };

      # Generate a config for a virtual host/hypervisor system too.
      # This allows us to generate the necessary Systemd unit files
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
              options.nixosContainer = containerOptions;

              config.assertions = containerAssertions {
                inherit lib; containerConfig = config.nixosContainer;
              };
            })
            ({ config, ... }: {
              # A bit of a hack.. Use the imperative container's config as a
              # declarative container. This will fill in the required parts of
              # the module configuration to generate the Systemd units.
              nixos.containers.instances."${name}" = config.nixosContainer // {
                system-config.imports = modules ++ [{
                  # Add the nixosContainer option to the container itself
                  # to prevent undefined option errors. It won't actually be evaluated.
                  options.nixosContainer = containerOptions;
                }];
              };
            })
          ] ++ modules;
        };

      containerSystem = host.config.nixos.containers.instances."${name}".system-config;

      nspawnUnit = host.config.environment.etc."systemd/nspawn/${name}.nspawn".source;
      networkUnits = pkgs.lib.mapAttrsToList
        (name: value: "${value.unit}/${name}")
        host.config.systemd.network.units;
    in
    pkgs.buildEnv {
      inherit name;
      # This passthru allows for debugging the config in nix repl.
      # e.g. importing the flake and then viewing the config attr
      # of a mkContainer result.
      passthru.config = containerSystem.config;
      paths = [
        containerSystem.config.system.build.toplevel
        (pkgs.symlinkJoin {
          name = "nixos-nspawn-data";
          paths = [
            # We need to add a JSON copy of the nixosContainer options so that
            # nixos_nspawn can generate the relevant systemd units.
            (pkgs.writeTextDir
              "data.json"
              (builtins.toJSON host.config.nixosContainer)
            )
            # Grab any systemd units that need to be installed on the host
            # Since it's a single unit, we need to put it in a folder
            (pkgs.linkFarm "nspawn-units" { "${name}.nspawn" = nspawnUnit; })
          ] ++ networkUnits;
          # Move everything into a subfolder so that when buildEnv
          # flattens the paths we have a nixos-nspawn folder.
          postBuild = ''
            cd $out
            mkdir -p .nixos-nspawn
            mv * .nixos-nspawn/
            mv {.,}nixos-nspawn
          '';
        })
      ];
    };
}
