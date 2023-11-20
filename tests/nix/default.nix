{ system ? builtins.currentSystem
, config ? { }
, nixpkgs ? <nixpkgs>
, pkgs ? import nixpkgs { inherit system config; }
, self
}:

{
  basic = import ./basic.nix { inherit nixpkgs self; } { inherit system pkgs; };
}
