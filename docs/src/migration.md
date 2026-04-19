# Migration from the `containers` module

This repository aims to replace the [containers](https://search.nixos.org/options?query=containers.)
module provided by nixpkgs/NixOS.

Migrating an existing container is straight forward. Consider the following configuration:

```nix
{
  containers.mycontainer = {
    # System configuration option is unchanged
    config = { pkgs, ... }: {
      services.nginx.enable = true;
      networking.firewall.allowedTCPPorts = [ 80 ];
    };

    # Old mount configuration
    bindMounts = {
      "/home" = {
        hostPath = "/home/alice";
        isReadOnly = false;
      };
    };

    # Old networking configuration
    hostAddress = "10.231.136.1";
    localAddress = "10.231.136.2";
  };
}
```

The migrated configuration looks like this:

```nix
  nixos.containers.mycontainer = {
    # Unchanged system configuration
    config = { pkgs, ... }: {
      services.nginx.enable = true;
      networking.firewall.allowedTCPPorts = [ 80 ];
    };

    # New mount configuration
    bindMounts = [
      "/home/alice:/home"
    ];

    # New networking configuration
    # The blank entry clears any inherited addresses.
    hostNetworkConfig.address = [ "" "10.231.136.1/28" ];
    containerNetworkConfig.address = [ "" "10.231.136.2/28" ];
  };
```

## Further reading

- [Networking configuration](./networking.md) is a comprehensive guide on container networking.
- [Options reference](./options/container.md) for all `nixosContainer` options.
