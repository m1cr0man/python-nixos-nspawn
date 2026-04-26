# Imperative container management

The `nixos-nspawn` utility provided by this repo is responsible for all CRUD operations on
systemd-nspawn NixOS containers.

Nspawn containers are particularly useful for breaking up large monolithic NixOS systems into
many smaller container configurations. This has a number of advtanges:

- Speeds up nixos-rebuild evaluation for the host system.
- Separates nixpkgs updates for groups of services, avoiding the "all-or-nothing" update procedure
  of classic NixOS deployments.
- Allows for isolated testing of new services and configuration.

These containers can also be used on systems that are not NixOS.
See the [installation instructions](./installation.md) on how to get prepared to run nixos-nspawn
containers on other distributions.

## Defining your container configuration

Similar to nixos-rebuild, you must define a Nix configuration either as a "classic" config or
using flakes.

### Flake-based configuration starter

You can use `nixos-nspawn.lib.mkContainer` provided by this repo to build containers:

```nix
{
  description = "The simplest flake for nixos-nspawn --flake";

  inputs = {
    nixpkgs.url = "nixpkgs";
    nixos-nspawn.url = "github:m1cr0man/python-nixos-nspawn";
  };

  outputs = { self, nixpkgs, nixos-nspawn }: {
    # nixosContainers is the key that nixos-nspawn looks for.
    nixosContainers = {
      mycontainer = nixos-nspawn.lib.mkContainer {
        inherit nixpkgs;
        name = "mycontainer";
        system = "x86_64-linux";
        modules = [
          {
            system.stateVersion = "26.05";
            services.nginx.enable = true;
            networking.firewall.allowedTCPPorts = [ 80 ];

            nixosContainer.bindMounts = [
              "/var/lib/host/path:/var/lib/container/path"
            ];
          }
          # You may import more .nix files as you wish.
          ./configuration.nix
        ];
      };
    };
  };
}
```

You can instantiate the container like so:

```sh
sudo nixos-nspawn create --flake .#mycontainer mycontainer
```

A full list of `nixosContainer` options is available in the [options reference](./options/container.md).

### Config-based configuration starter

Although we strongly recommend using flakes, you can also use classic configuration.nix files

```nix
# Just a regular configuration.nix
{
  system.stateVersion = "26.05";
  services.nginx.enable = true;
  networking.firewall.allowedTCPPorts = [ 80 ];
}
```

You can instantiate the container like so:

```sh
sudo nixos-nspawn create --config configuration.nix mycontainer
```

## Switching to declarative containers

It is quite safe to move between imperative and declarative containers (and vice-versa).
The process involves:

- Remove the container with `nixos-nspawn remove $container`.
- Rejigging your configuration to add the imperative container to your host's `nixos.containers`
  (see the [declarative container docs](./declarative.md)).
- Performing `nixos-rebuild` on the host.

Since the same state directories are used for both kinds of containers, no other changes are
required.

## Update, delete, rollback, and other operations

Check out the `nixos-nspawn --help` output for more documentation on common imperative operations.

## Further reading

- [Networking configuration](./networking.md) is a comprehensive guide on container networking.
- [Upstream tooling](./upstream-tooling.md) covers other CLI tools provided by systemd for
  container management.
- [CLI Reference](./cli.md) for `nixos-nspawn`.
- [Options reference](./options/container.md) for all `nixosContainer` options.
