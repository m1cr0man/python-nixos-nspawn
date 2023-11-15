{ config, nixpkgs, name, system ? builtins.currentSystem }:
(import ./lib.nix).mkContainer {
  inherit nixpkgs name system;
  modules = [ config ];
}
