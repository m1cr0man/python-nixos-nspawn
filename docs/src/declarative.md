# Declarative container management

Declarative containers have existed in NixOS for quite some time under the `containers` option.
This repository provides [RFC108](https://github.com/NixOS/rfcs/blob/master/rfcs/0108-nixos-containers.md)-style
containers which use systemd-networkd instead of the classic script based networking.

## Defining your container configuration

You should have already added the hypervisor module to your system during [installation](./installation.md).

From here, you can simply declare NixOS containers in your host configuration like so:

```nix
{
  nixos.containers.mycontainer = {
    # This option houses the actual system configuration.
    config = {
      services.nginx.enable = true;
      networking.firewall.allowedTCPPorts = [ 80 ];
    };

    bindMounts = [
      "/var/lib/host/path:/var/lib/container/path"
    ];
  };
}
```

Upon `nixos-rebuild`, the container will be started. You can verify this with `nixos-nspawn list`
or `machinectl list`.

## Further reading

- [Networking configuration](./networking.md) is a comprehensive guide on container networking.
- [Upstream tooling](./upstream-tooling.md) covers other CLI tools provided by systemd for
  container management.
- [Options reference](./options/declarative.md) for all `nixos.containers` options.
