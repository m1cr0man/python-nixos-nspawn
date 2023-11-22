{ system ? builtins.currentSystem
, config ? { }
, nixpkgs ? <nixpkgs>
, pkgs ? import nixpkgs { inherit system config; }
, self
}:

{
  basic = import ./basic.nix { inherit nixpkgs self; } { inherit system pkgs; };
  nat = import ./nat.nix { inherit nixpkgs self; } { inherit system pkgs; };
  macvlan = import ./macvlan.nix { inherit nixpkgs self; } { inherit system pkgs; };
}
