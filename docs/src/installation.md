# Installation (NixOS)

The simplest way to get access to both imperative and declarative container management is
to install this flake's module and overlay like so:

```nix
{
  inputs = {
    nixpkgs.url = "nixpkgs";
    # STEP 1: Add this to your flake inputs
    nixos-nspawn.url = "github:m1cr0man/python-nixos-nspawn";
  };

  outputs = { self, nixpkgs, nixos-nspawn }: {
    nixsConfigurations = {
      myhost = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          # STEP 2: Add the flake's module to your host system
          nixos-nspawn.nixosModules.hypervisor
          {
            # STEP 3: Add the overlay to expose the nixos-nspawn package
            nixpkgs.overlays = [nixos-nspawn.overlays.default];
          }
        ];
      };
    };
  };
}
```

NixOS is currently lacking some critical features for imperative container management.
You will need to incorporate the changes from [NixOS PR #216025](https://github.com/NixOS/nixpkgs/pull/216025)
to ensure that your containers can be started properly and do not get stopped unintentionally
during switch-to-configuration. A quick workaround is to use the nixpkgs branch from that PR:

```nix
    nixpkgs.url = "github:m1cr0man/nixpkgs/rfc108-minimal";
```

Otherwise, you can simply install the `nixos-nspawn` package from this flake however
you wish.

# Installation (Nix on other distros)

Imperative NixOS containers can be used on any distribution subject to meeting these requirements:

- Nix package manager is installed and available.
- systemd-networkd is responsible for network configuration.
- Both /var/lib/machines and /etc/systemd/nspawn are writable and persistent.

The easiest way to run the `nixos-nspawn` binary is:

```sh
nix run github:m1cr0man/python-nixos-nspawn -- --help
# For a _real_ test, try the example container
sudo nix run github:m1cr0man/python-nixos-nspawn -- create --flake github:m1cr0man/python-nixos-nspawn#example example
```
