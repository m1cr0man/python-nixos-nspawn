{ system ? builtins.currentSystem
, config ? { }
, nixpkgs ? <nixpkgs>
, pkgs ? import nixpkgs { inherit system config; }
, self
}:
let
  nixos-lib = import (nixpkgs + "/nixos/lib") { inherit (pkgs) lib; };
  runTest = module: nixos-lib.runTest {
    _module.args.self = self;
    imports = [ module ];

    # Per-node default options. Think of this as a module imported on all nodes.
    defaults = {
      system.stateVersion = "24.11";
    };

    # Required to avoid dupe import of nixpkgs + ensure overlays are available
    # https://github.com/NixOS/nixpkgs/blob/8cb39ebf286e8cb64e4ffcddb296be0ff6957ca8/nixos/lib/testing/nodes.nix#L105
    node.pkgs = pkgs;
    hostPkgs = pkgs;
  };
in
{
  basic = runTest ./basic.nix;
}
