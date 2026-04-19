{
  inputs.nixpkgs.url = "github:m1cr0man/nixpkgs/rfc108-minimal";

  outputs = inputs: {
    packages.x86_64-linux =
      let
        pkgs = import inputs.nixpkgs { system = "x86_64-linux"; };

        eval =
          options:
          pkgs.lib.evalModules {
            modules = [
              (args: {
                options = options // {
                  # Hide NixOS `_module.args` from nixosOptionsDoc to remain specific to this repo
                  _module.args = args.lib.mkOption { internal = true; };
                };
              })
            ];
          };

        mkOptionsDoc =
          options:
          pkgs.nixosOptionsDoc {
            inherit (eval options) options;
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

        containerOptions = import ../nixos_nspawn/nix/containers-next/container-options.nix {
          inherit pkgs;
          inherit (pkgs) lib;
          name = "<name>";
          declarative = true;
        };

        # Defining a pseudo options group so that we avoid redefining the container options
        # on both imperative and declarative options pages.
        imperativeOptions = {
          nixosContainer = pkgs.lib.mkOption {
            type = pkgs.lib.types.attrs;
            default = { };
            description = ''
              The container configuration. See [container options](container.md) for a full list of options.
            '';
            example = pkgs.lib.literalExpression ''
              bindMounts = [
                "/path/on/host:/path/on/container"
              ];
            '';
          };
        };

        declarativeOptionsOrig =
          (import ../nixos_nspawn/nix/containers-next/hypervisor.nix {
            inherit pkgs;
            inherit (pkgs) lib;
            config = null;
          }).options.nixos.containers;

        declarativeOptions = {
          nixos.containers = declarativeOptionsOrig // {
            instances = pkgs.lib.mkOption {
              type = pkgs.lib.types.attrsOf pkgs.lib.types.attrs;
              default = { };
              description = ''
                Container configurations. See [container options](container.md) for a full list of options.
              '';
              example = pkgs.lib.literalExpression ''
                mycontainer = {
                  system-config = {
                    services.openssh.enable = true;
                  };
                };
              '';
            };
          };
        };

        containerDocs = mkOptionsDoc containerOptions;
        imperativeDocs = mkOptionsDoc imperativeOptions;
        declarativeDocs = mkOptionsDoc declarativeOptions;

        imperativeHeader = ''
          The system can be configured as if it were a usual NixOS configuration.
          The following additional option is added for nixos-nspawn-specific settings:
        '';
      in
      {
        default = pkgs.stdenv.mkDerivation {
          name = "nixos-nspawn-docs";
          src = pkgs.lib.cleanSource ../.;
          nativeBuildInputs = [ pkgs.mdbook ];
          patchPhase = ''
            mkdir -p docs/src/options
            cat ${containerDocs.optionsCommonMark} > docs/src/options/container.md
            cat > docs/src/options/imperative.md << EOF
            ${imperativeHeader}
            EOF
            cat ${imperativeDocs.optionsCommonMark} >> docs/src/options/imperative.md
            cat ${declarativeDocs.optionsCommonMark} > docs/src/options/declarative.md
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
