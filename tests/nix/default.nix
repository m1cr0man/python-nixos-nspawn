{ system ? builtins.currentSystem
, config ? { }
, nixpkgs ? <nixpkgs>
, pkgs ? import nixpkgs { inherit system config; }
, self
}:
let
  nixos-lib = import (nixpkgs + "/nixos/lib") { inherit (pkgs) lib; };
  runTest' = { module, enableHypervisor }: nixos-lib.runTest {
    _module.args.self = self;
    imports = [
      module
      { meta.maintainers = with pkgs.lib.maintainers; [ ma27 m1cr0man ]; }
    ];

    # Per-node default options. Think of this as a module imported on all nodes.
    defaults = {
      system.stateVersion = "24.11";
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
  basic = runTest ./basic.nix;
  config-activation = runTest ./config-activation.nix;
  daemon-mount = runTest ./daemon-mount.nix;
  imperative = runTest ./imperative.nix;
  macvlan = runTest ./macvlan.nix;
  nat = runTest ./nat.nix;
  migration = runTestNoHV ./migration.nix;
  wireguard = runTest ./wireguard.nix;
}
