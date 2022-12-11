{
  inputs = {
    nixpkgs.url = "nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      name = "nixos-nspawn";
      version = with builtins; head (split "[:space:\n]+" (readFile "${self}/nixos_nspawn/version.txt"));
      pythonVersion = "python310";
    in
    {
      overlays = {
        default = self.overlays."${name}";
        "${name}" = (final: prev: {
          "${name}" =
            let
              pyPkgs = final."${pythonVersion}Packages";
            in
            pyPkgs.buildPythonPackage {
              inherit version;
              pname = name;
              src = self;
              format = "pyproject";

              buildInputs = [ pyPkgs.poetry ];
              propagatedBuildInputs = [ pyPkgs.rich ];

              patches = [
                # Need to compile in the system architecture.
                # The Nix tools do the same thing.
                (final.writeText
                  "nixos_nspawn_set_system.patch"
                  ''
                    --- a/nixos_nspawn/system.txt
                    +++ b/nixos_nspawn/system.txt
                    @@ -1 +1 @@
                    -x86_64-linux
                    +${final.hostPlatform.system}
                  '')
              ];

              checkPhase = ''
                $out/bin/nixos-nspawn list > /dev/null
              '';

              meta = {
                name = "${name}-${version}";
                description = "RFC 108 imperative container manager";
              };
            };
        });
      };

      lib = import "${self}/nixos_nspawn/nix/lib.nix";

    } // (flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import "${nixpkgs}/pkgs/top-level/default.nix" {
          localSystem.system = system;
          overlays = [ self.overlays.default ];
          config = { };
        };

        python = pkgs."${pythonVersion}";
      in
      rec {
        packages = {
          default = pkgs."${name}";
          "${name}" = packages.default;
          sudo-nspawn = import "${self}/nix/sudo-nspawn.nix" { inherit (pkgs) sudo; };
        };

        apps = {
          default = flake-utils.lib.mkApp { drv = packages.default; };
          "${name}" = apps.default;
        };

        devShells = {
          default = (python.withPackages (pyPkgs: [ pyPkgs.poetry pyPkgs.rich ])).env;
        };

        # Nix < 2.7 compatibility
        defaultPackage = packages.default;
        defaultApp = apps.default;
        devShell = devShells.default;

        # Example container
        nixosContainers.example = self.lib.mkContainer {
          inherit nixpkgs system;
          name = "example";
          modules = [
            ({ pkgs, ... }: {
              system.stateVersion = system;
              environment.systemPackages = [ pkgs.python311 ];
            })
          ];
        };

      }));
}
