{
    inputs = {
        nixpkgs.url = "nixpkgs";
    };

    outputs = { self, nixpkgs }: let
        system = "x86_64-linux";
        pkgs = import "${nixpkgs}/pkgs/top-level/default.nix" {
            localSystem.system = system;
            overlays = [];
            config = {};
        };

        name = "nixos-nspawn";

        python = pkgs.python310;

        prodDeps = pypi: with pypi; [
            rich
        ];

        devDeps = pypi: with pypi; [
            setuptools
        ];

        allDeps = pypi: (prodDeps pypi) ++ (devDeps pypi);
    in {

        packages."${system}" = rec {
            default = python.pkgs.buildPythonPackage {
                pname = name;
                version = builtins.readFile "${self}/nixos_nspawn/version.txt";
                src = "${self}/";
                buildInputs = devDeps python.pkgs;
                propagatedBuildInputs = prodDeps python.pkgs;
            };
            "${name}" = default;
        };

        apps."${system}" = rec {
            default = {
                type = "app";
                program = "${python.pkgs.toPythonApplication self.packages."${system}".default}/bin/${name}";
            };
            "${name}" = default;
        };

        # Nix < 2.7 compatibility
        defaultPackage."${system}" = self.packages."${system}".default;
        defaultApp."${system}" = self.apps."${system}".default;

        # devShell."${system}" = pkgs.mkShell {
        #     name = "${name}-dev";
        #     buildInputs = [
        #         (python.withPackages allDeps)
        #     ];
        # };
        # Simpler, equivalent method...
        devShell."${system}" = (python.withPackages allDeps).env;
    };
}
