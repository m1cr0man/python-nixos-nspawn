{
  inputs = {
    nixpkgs.url = "nixpkgs";
    poetry2nix = {
      url = "github:nix-community/poetry2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, poetry2nix, flake-utils }:
    let
      name = "nixos-nspawn";
      version = builtins.readFile "${self}/nixos_nspawn/version.txt";
      pythonVersion = "python310";

      projectDir = self;

      customOverrides = (pyself: pysuper: {
        # flake8-annotations is missing poetry-core when parsed by poetry2nix
        flake8-annotations = pysuper.flake8-annotations.overridePythonAttrs (oldAttrs: {
          nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [ pysuper.poetry-core ];
        });
        # flake8-assertive is missing setuptools when parsed by poetry2nix
        flake8-assertive = pysuper.flake8-annotations.overridePythonAttrs (oldAttrs: {
          nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [ pysuper.setuptools ];
        });
        # flake8-comprehensions is missing setuptools when parsed by poetry2nix
        flake8-comprehensions = pysuper.flake8-annotations.overridePythonAttrs (oldAttrs: {
          nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [ pysuper.setuptools ];
        });
      });
    in
    {
      overlays = {
        default = nixpkgs.lib.composeManyExtensions [
          poetry2nix.overlay
          self.overlays."${name}"
        ];
        "${name}" = (final: prev: {
          "${name}" = prev.poetry2nix.mkPoetryApplication {
            inherit projectDir;
            python = prev."${pythonVersion}";
            overrides = prev.poetry2nix.overrides.withDefaults customOverrides;
            # Skip installing dev-dependencies
            # https://github.com/nix-community/poetry2nix/issues/47
            doCheck = false;
            meta = {
              name = "${name}-${version}";
            };
          };
        });
      };

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
          "${name}-venv" = pkgs.poetry2nix.mkPoetryEnv {
            inherit python projectDir;
            overrides = pkgs.poetry2nix.overrides.withDefaults customOverrides;
          };
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
      }));
}
