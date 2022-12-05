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
    in
    pkgs.buildEnv {
      inherit name;
      # We need to add a JSON copy of the nixosContainer options so that
      # nixos_nspawn can generate the relevant systemd units.
      paths = [
        container.config.system.build.toplevel
        (pkgs.writeTextDir "data" (builtins.toJSON container.config.nixosContainer))
      ];
    };
}
