{
  mkContainer =
    {
      nixpkgs ? null,
      pkgs ? null,
      name,
      system,
      modules ? [ ],
    }:
    let
      pkgs' =
        if nixpkgs == null then
          pkgs
        else
          import "${nixpkgs}/pkgs/top-level/default.nix" {
            localSystem.system = system;
          };

      shared = import ./containers-next/shared.nix { inherit (pkgs') lib; };

      containerOptions = import ./containers-next/container-options.nix {
        inherit name;
        inherit (pkgs') lib;
        pkgs = pkgs';
        declarative = false;
      };

      containerAssertions =
        { containerConfig, lib }:
        [
          {
            assertion = containerConfig.sharedNix;
            message = "Experimental 'sharedNix'-feature isn't supported for imperative containers!";
          }
          {
            assertion = containerConfig.activation.strategy != "dynamic";
            message = "'dynamic' is currently not supported for imperative containers!";
          }
        ];

      containerWarnings =
        { lib }:
        [
          (lib.optionalString (nixpkgs != null && pkgs != null) ''
            Both nixpkgs and pkgs set in call to mkContainer, which will result in
            many extra evaluations of nixpkgs. If you expect pkgs to be used,
            unset nixpkgs, and vice versa.
          '')
        ];

      # Generate a config for a virtual host/hypervisor system too.
      # This allows us to generate the necessary Systemd unit files
      # for the container in Nix. They are put in place by the Python
      # code after evaluation.
      host = import "${pkgs'.path}/nixos/lib/eval-config.nix" {
        inherit system;
        inherit (pkgs') lib;
        pkgs = pkgs';
        modules = [
          ./containers-next/hypervisor.nix
          (
            {
              config,
              pkgs,
              lib,
              ...
            }:
            {
              # Add the nixosContainer option to this system so that
              # the imperative container's configuration can be parsed.
              options.nixosContainer = containerOptions;

              config = {
                assertions = containerAssertions {
                  inherit lib;
                  containerConfig = config.nixosContainer;
                };
                warnings = containerWarnings { inherit lib; };

                # A bit of a hack.. Use the imperative container's config as a
                # declarative container. This will fill in the required parts of
                # the module configuration to generate the Systemd units.
                nixos.containers.instances."${name}" = config.nixosContainer // {
                  # nixpkgs is not inherited here as the host's pkgs will already point to nixpkgs
                  # and so we can avoid evaluating it again.
                  declarative = lib.mkForce false;
                  config.imports = modules ++ [
                    {
                      # Add the nixosContainer option to the container itself
                      # to prevent undefined option errors. It won't actually be evaluated.
                      options.nixosContainer = containerOptions;
                      config.assertions = containerAssertions {
                        inherit lib;
                        containerConfig = config.nixosContainer;
                      };
                      config.warnings = containerWarnings { inherit lib; };
                    }
                  ];
                };
              };
            }
          )
          # Modules added here to load the user's nixosContainer settings.
        ]
        ++ modules;
      };

      containerInstance = host.config.nixos.containers.instances."${name}";
      containerSystem = containerInstance.config;

      nspawnUnit = host.config.systemd.nspawn.${name}.unit;
      serviceOverrides =
        pkgs'.writeText "overrides.conf"
          host.config.systemd.units."systemd-nspawn@${name}.service".text;
      jsonConfig = pkgs'.writeText "data.json" (shared.jsonContent containerInstance);

      # Only select network units defined by this module.
      nspawnNetworks = pkgs'.lib.optionals (
        containerInstance.hostNetworkConfig != null && containerInstance.zone == null
      ) [ "20-${shared.ifacePrefix "veth"}-${name}.network" ];
      networkUnits = builtins.map (name: host.config.systemd.network.units."${name}".unit) nspawnNetworks;
    in
    pkgs'.buildEnv {
      inherit name;
      # This passthru allows for debugging the config in nix repl.
      # e.g. importing the flake and then viewing the config attr
      # of a mkContainer result.
      passthru.config = containerSystem.config;
      passthru.host = host.config;
      paths = [
        containerSystem.config.system.build.toplevel
        (pkgs'.symlinkJoin {
          name = "nixos-nspawn-data";
          paths = [
            # Grab any config files that need to be installed on the host
            # Since it's a single unit, we need to put it in a folder
            (pkgs'.linkFarm "nspawn-data" ({
              "${name}.nspawn" = nspawnUnit;
              "service-overrides.conf" = serviceOverrides;
              "data.json" = jsonConfig;
            }))
          ]
          ++ networkUnits;
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
