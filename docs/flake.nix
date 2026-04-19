{
  inputs.nixpkgs.url = "github:m1cr0man/nixpkgs/rfc108-minimal";

  outputs = inputs: {
    packages.x86_64-linux =
      let
        pkgs = import inputs.nixpkgs { system = "x86_64-linux"; };

        options = import ../nixos_nspawn/nix/containers-next/container-options.nix {
          inherit pkgs;
          inherit (pkgs) lib;
          name = "<name>";
          declarative = true;
        };

        eval = pkgs.lib.evalModules {
          modules = [
            (args: {
              options = options // {
                # Hide NixOS `_module.args` from nixosOptionsDoc to remain specific to this repo
                _module.args = args.lib.mkOption { internal = true; };
              };
            })
          ];
        };

        optionsDoc = pkgs.nixosOptionsDoc {
          inherit (eval) options;
          transformOptions =
            o:
            o
            // {
              declarations = map (
                declaration:
                let
                  # Rewrite nix store paths to web paths
                  flakeOutPath = inputs.self.sourceInfo.outPath;
                  name = pkgs.lib.removePrefix "${flakeOutPath}/" declaration;
                in
                if pkgs.lib.hasPrefix "${flakeOutPath}/" declaration then
                  {
                    inherit name;
                    url = "https://github.com/m1cr0man/python-nixos-nspawn/blob/main/${name}";
                  }
                else
                  declaration
              ) o.declarations;
            };
        };
      in
      {
        default = pkgs.stdenv.mkDerivation {
          name = "nixos-nspawn-docs";
          src = pkgs.lib.cleanSource ../.;
          nativeBuildInputs = [ pkgs.mdbook ];
          patchPhase = ''
            cat ${optionsDoc.optionsCommonMark} > docs/src/configuration-options.md
            cp README.md docs/src
          '';
          buildPhase = ''
            cd docs
            mdbook build
          '';
          installPhase = "cp -vr book $out";
        };
      };
  };
}
