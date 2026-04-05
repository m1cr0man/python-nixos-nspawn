{
  inputs = {
    nixpkgs.url = "github:m1cr0man/nixpkgs/rfc108-minimal";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      name = "nixos-nspawn";
      version = with builtins; head (split "[:space:\n]+" (readFile "${self}/nixos_nspawn/version.txt"));
      nspawnNix = "${self}/nixos_nspawn/nix";
    in
    {
      overlays = {
        default = (final: prev: (
          (self.overlays."${name}" final prev)
          // (self.overlays.sudo-nspawn final prev)
        ));
        sudo-nspawn = (final: prev: {
          sudo-nspawn = import "${self}/nixos_nspawn/nix/sudo-nspawn.nix" {
            inherit (prev) sudo;
          };
        });
        "${name}" = (final: prev: {
          # Use pythonPackageExtensions so that any supported version of Python can be used
          "${name}" = prev.python3Packages."${name}";
          pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
            (python-final: python-prev: {
              "${name}" = python-prev.buildPythonPackage {
                inherit version;
                pname = name;
                src = self;
                disabled = python-prev.pythonOlder "3.11";

                format = "pyproject";
                buildInputs = [ python-prev.setuptools ];
                propagatedBuildInputs = [ python-prev.rich ];

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
                      +${final.stdenv.hostPlatform.system}
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
            })
          ];
        });
      };

      lib = import "${nspawnNix}/lib.nix";

      nixosModules.hypervisor = "${nspawnNix}/containers-next/hypervisor.nix";

    } // (flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          localSystem.system = system;
          overlays = [ self.overlays.default ];
          config = { };
        };
      in
      rec {
        packages = {
          default = pkgs."${name}";
          "${name}" = packages.default;
          sudo-nspawn = import "${self}/nixos_nspawn/nix/sudo-nspawn.nix" { inherit (pkgs) sudo; };
        };

        apps = {
          default = flake-utils.lib.mkApp { drv = packages.default; };
          "${name}" = apps.default;
        };

        devShells = {
          default = (pkgs.python3.withPackages (pyPkgs: [ pyPkgs.rich ])).env.overrideAttrs (prev: {
            nativeBuildInputs = prev.nativeBuildInputs ++ [ pkgs.ruff pkgs.ty ];
          });
        };

        checks = import "${self}/tests/nix"
          {
            inherit system pkgs nixpkgs self;
          };

        # Example container
        nixosContainers.example = self.lib.mkContainer {
          inherit system pkgs;
          name = "example";
          modules = [
            ({ pkgs, ... }: {
              system.stateVersion = "25.11";
              environment.systemPackages = [ pkgs.python314 ];
              nixosContainer.forwardPorts = [{ hostPort = 12345; containerPort = 12345; }];
            })
          ];
        };

      }));
}
