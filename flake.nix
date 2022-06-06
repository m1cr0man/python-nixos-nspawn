{
    inputs = {
        nixpkgs.url = "nixpkgs";
        poetry2nix = {
            url = "github:nix-community/poetry2nix";
            inputs.nixpkgs.follows = "nixpkgs";
        };
        flake-utils.url = "github:numtide/flake-utils";
    };

    outputs = { self, nixpkgs, poetry2nix, flake-utils }: flake-utils.lib.eachDefaultSystem (system: let
        name = "nixos-nspawn";
        version = builtins.readFile "${self}/nixos_nspawn/version.txt";
        python = pkgs.python310;

        projectDir = self;

        pkgs = import "${nixpkgs}/pkgs/top-level/default.nix" {
            localSystem.system = system;
            overlays = [ poetry2nix.overlay ];
            config = {};
        };

        # self & super refers to poetry2nix
        p2n = pkgs.poetry2nix.overrideScope' (self: super: {
            # pyself & pysuper refers to python packages
            defaultPoetryOverrides = super.defaultPoetryOverrides.extend (pyself: pysuper: {
                # flake8-annotations is missing poetry-core when parsed by poetry2nix
                flake8-annotations = pysuper.flake8-annotations.overridePythonAttrs (oldAttrs: {
                    nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [ pysuper.poetry-core ];
                });
            });
        });
    in rec {
        packages = {
            default = p2n.mkPoetryApplication {
                inherit python projectDir;
                # Skip installing dev-dependencies
                # https://github.com/nix-community/poetry2nix/issues/47
                # doCheck = false;
                meta = {
                    name = "${name}-${version}";
                };
            };
            "${name}" = packages.default;
            "${name}-venv" = (p2n.mkPoetryEnv {
                inherit python projectDir;
            }).overrideAttrs (final: prev: { nativeBuildInputs = prev.nativeBuildInputs ++ [ python.pkgs.poetry ]; });
        };

        apps = {
            default = flake-utils.lib.mkApp { drv = packages.default; };
            "${name}" = apps.default;
        };

        devShells = {
            default = packages."${name}-venv".env;
            poetry = (python.withPackages (pyPkgs: [ pyPkgs.poetry ])).env;
        };

        # Nix < 2.7 compatibility
        defaultPackage = packages.default;
        defaultApp = apps.default;
        devShell = devShells.default;
    });
}
