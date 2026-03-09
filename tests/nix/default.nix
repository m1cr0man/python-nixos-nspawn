{ system ? builtins.currentSystem
, config ? { }
, nixpkgs ? <nixpkgs>
, pkgs ? import nixpkgs { inherit system config; }
, self
}:
let
  nixos-lib = import (pkgs.path + "/nixos/lib/testing/default.nix") { inherit (pkgs) lib; };
  runTest' = { module, enableHypervisor }: nixos-lib.runTest {
    _module.args.self = self;
    imports = [
      module
      { meta.maintainers = with pkgs.lib.maintainers; [ ma27 m1cr0man ]; }
    ];

    # Per-node default options. Think of this as a module imported on all nodes.
    defaults = {
      system.stateVersion = "25.11";
      networking.useNetworkd = true;
      imports = pkgs.lib.optionals enableHypervisor [
        self.nixosModules.hypervisor
      ];
    };

    # Required to avoid dupe import of nixpkgs + ensure overlays are available
    # https://github.com/NixOS/nixpkgs/blob/8cb39ebf286e8cb64e4ffcddb296be0ff6957ca8/nixos/lib/testing/nodes.nix#L105
    node.pkgs = pkgs;
    hostPkgs = pkgs;
  };
  runTest = module: runTest' { inherit module; enableHypervisor = true; };
  runTestNoHV = module: runTest' { inherit module; enableHypervisor = false; };
in
{
  basic = runTest "${self}/tests/nix/basic.nix";
  config-activation = runTest "${self}/tests/nix/config-activation.nix";
  daemon-mount = runTest "${self}/tests/nix/daemon-mount.nix";
  imperative = runTest "${self}/tests/nix/imperative.nix";
  macvlan = runTest "${self}/tests/nix/macvlan.nix";
  nat = runTest "${self}/tests/nix/nat.nix";
  migration = runTestNoHV "${self}/tests/nix/migration.nix";
  wireguard = runTest "${self}/tests/nix/wireguard.nix";
}
