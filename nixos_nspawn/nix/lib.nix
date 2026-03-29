rec {

  containerAssertions = { containerConfig, lib }: [
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
    { nixpkgs ? null
    , name
    , system
    , pkgs ? (import "${nixpkgs}/pkgs/top-level/default.nix" { localSystem.system = system; })
    , modules ? [ ]
    }:
    let
      shared = import ./containers-next/shared.nix { inherit (pkgs) lib; };
      inherit (shared) ifacePrefix;

      containerOptions = import ./containers-next/container-options.nix {
        inherit pkgs name;
        inherit (pkgs) lib;
        declarative = false;
      };

      # Generate a config for a virtual host/hypervisor system too.
      # This allows us to generate the necessary Systemd unit files
      # for the container in Nix. They are put in place by the Python
      # code after evaluation.
      host = import "${pkgs.path}/nixos/lib/eval-config.nix"
        {
          inherit pkgs system;
          inherit (pkgs) lib;
          modules = [
            ./containers-next/hypervisor.nix
            ({ config, pkgs, lib, ... }: {
              # Add the nixosContainer option to this system so that
              # the imperative container's configuration can be parsed.
              options.nixosContainer = containerOptions;

              config = {
                assertions = containerAssertions {
                  inherit lib; containerConfig = config.nixosContainer;
                };

                # A bit of a hack.. Use the imperative container's config as a
                # declarative container. This will fill in the required parts of
                # the module configuration to generate the Systemd units.
                nixos.containers.instances."${name}" = config.nixosContainer // {
                  inherit nixpkgs;
                  declarative = lib.mkForce false;
                  system-config.imports = modules ++ [{
                    # Add the nixosContainer option to the container itself
                    # to prevent undefined option errors. It won't actually be evaluated.
                    options.nixosContainer = containerOptions;
                    config.assertions = containerAssertions {
                      inherit lib; containerConfig = config.nixosContainer;
                    };
                  }];
                };
              };
            })
          # Modules added here to load the user's nixosContainer settings.
          ] ++ modules;
        };

      containerInstance = host.config.nixos.containers.instances."${name}";
      containerSystem = containerInstance.system-config;

      nspawnUnit = host.config.systemd.nspawn.${name}.unit;
      serviceOverrides = pkgs.writeText "overrides.conf" host.config.systemd.units."systemd-nspawn@${name}.service".text;
      jsonConfig = pkgs.writeText "data.json" (builtins.toJSON (
        builtins.removeAttrs containerInstance [ "system-config" "nixpkgs" "toplevel" ]
      ));

      # Only select network units defined by this module.
      nspawnNetworks = pkgs.lib.optionals
        (containerInstance.network != null && containerInstance.zone == null)
        [ "20-${ifacePrefix "veth"}-${name}.network" ];
      networkUnits = builtins.map
        (name: host.config.systemd.network.units."${name}".unit)
        nspawnNetworks;
    in
    pkgs.buildEnv {
      inherit name;
      # This passthru allows for debugging the config in nix repl.
      # e.g. importing the flake and then viewing the config attr
      # of a mkContainer result.
      passthru.config = containerSystem.config;
      passthru.host = host.config;
      paths = [
        containerSystem.config.system.build.toplevel
        (pkgs.symlinkJoin {
          name = "nixos-nspawn-data";
          paths = [
            # Grab any config files that need to be installed on the host
            # Since it's a single unit, we need to put it in a folder
            (pkgs.linkFarm "nspawn-data" ({
              "${name}.nspawn" = nspawnUnit;
              "service-overrides.conf" = serviceOverrides;
              "data.json" = jsonConfig;
            }))
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
