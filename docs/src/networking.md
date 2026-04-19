# Networking

Understanding container networking in the context of Systemd-nspawn can be a bit of a challenge.
A lack of widespread use of either systemd-networkd or systemd-nspawn makes it difficult to
determine the exact configuration you may be looking for when first configuring your containers.
This document aims to help you understand the configuration possibilities and when you may want
to use them.

## The Default Config

This imperative container configuration will be our control throughout the rest of this guide:

```nix
# example.nix
{
  system.stateVersion = "26.05";

  # Configure a basic web server. HTTP only, no TLS.
  services.nginx = {
    enable = true;
    virtualHosts.localhost.default = true;
  };
  networking.firewall.allowedTCPPorts = [ 80 ];

  # Expose the port via your host's network
  # *IMPORTANT:* Even if your host firewall would usually block this,
  # systemd-nspawn will configure nftables such that it will
  # work anyway.
  nixosContainer.forwardPorts = [{ hostPort = 8181; containerPort = 80; }];
}
```

You can create this container by writing the above config to a file and running this command:

```sh
nixos-nspawn create --config example.nix example
```

Out of the box, this provides:

- An IPv4 address for both the container and host.
- An IPv6 link-local address for both the container and host.
- IPv4 internet connectivity via NAT.
- Container DNS hostname resolution on the host only (via nss-mymachines).
- Connections to the host on port 8181 routed to your container (IPv4 Only).

All the following commands should work:

```sh
# Ping the container on IPv4
ping -4 -c1 example
# Ping the container on IPv6
# Note: If nscd/nsncd is enabled (default on NixOS), you need to specify the interface to use.
ping -6 -c1 -I ve-example example
# View the web server's homepage
curl -o- http://example
# Ping the internet from within the container
machinectl shell example $(which ping) -c1 nixos.org
```

## IPv6

IPv6 _technically_ works out of the box, but the link local address is not very useful:

- Port forwards only work on IPv4.
- IPv6 internet connectivity within the container does not work.

If you see the error `Destination unreachable: Beyond scope of source address`, keep reading.

### Global subnet delegation

If you have an IPv6 address block at your disposal, and you want your container to be reachable
on the internet, you can delegate a subnet of that address block to your container and host.

Note on Routing: Your host's upstream provider must be routing your subnet to your host's
external interface. If they rely on Neighbor Discovery (NDP) instead of static routing
(common with providers like Hetzner), you may also need to enable
`IPv6ProxyNDP = "yes";` on your host's main uplink interface.

### ULA (Private IPv6 with NAT)

A Unique Local Address (ULA) is equivalent to an IPv4 private subnet. This should be distinct
from any other IPv6 addresses on your host.

### Configuration

For both of the above cases, configuration is similar:

```nix
# example.nix
{
  # ... Below the default configuration ...
  nixosContainer.hostNetworkConfig.ipv6Prefixes = [{
    Prefix = "2001:1234:abcd:efgh::/64";
    # The host itself will need an address in this subnet to reach the container
    # and to serve a gateway. Assign will automatically pick an address to use.
    Assign = true;
  }];

  # Optional: Assign a static address to the container itself.
  # The gateway address will be resolved via router advertisement.
  nixosContainer.containerNetworkConfig = {
    address = [
      "2001:1234:abcd:efgh::2/64"
    ];
  };
}
```

## Zones

Zones are a systemd-nspawn abstraction over the basic setup of a hub and spoke bridge network.
A `vz-` prefixed interface will be created on the host side instead of a `ve-` interface.
Zones allow for private inter-container networking on the same host.

You can specify a zone interface to use like so:

```nix
# example.nix
{
  # ... Below the default configuration ...
  nixosContainer.zone = "myzone";
}
```

The host side of zone configuration must be specified declaratively via `nixos.containers.zones`
on the hypervisor. It cannot be configured via imperative container options.

## Bridges

Bridges work similarly to zones, but the creation of the bridge is not managed by systemd-nspawn.
You must create the bridge interface in advance of creating any containers which depend on it.

You can specify a bridge interface to use like so:

```nix
# example.nix
{
  # ... Below the default configuration ...
  nixosContainer.bridge = "mybridge";
}
```

## Gotchas

- nscd/nsncd (the protocol itself, infact) does not support passing around a Scope ID, required to
  make IPv6 link-local routing work without specifying the interface manually.
  This is why `ping -6` will resolve the IP but fail to ping the container
  without adding `-I ve-example`. You can observe this behaviour on NixOS with
  the following commands, noting the `%13` present on the last command:

```sh
$ ping -6 -c1 example
PING example (fe80::a4cf:97ff:fe11:8c36) 56 data bytes

--- example ping statistics ---
1 packets transmitted, 0 received, 100% packet loss, time 0ms

$ getent ahosts example
fe80::a4cf:97ff:fe11:8c36 STREAM example
fe80::a4cf:97ff:fe11:8c36 DGRAM
fe80::a4cf:97ff:fe11:8c36 RAW

$ LD_LIBRARY_PATH="$(nix eval --raw nixpkgs#systemd.outPath)/lib" getent -s mymachines ahosts example
fe80::a4cf:97ff:fe11:8c36%13 STREAM example
fe80::a4cf:97ff:fe11:8c36%13 DGRAM
fe80::a4cf:97ff:fe11:8c36%13 RAW
```

- Firewall rules configured for NAT and port forwarding are added to the io.systemd.nat table.
  The prerouting and output hooks have a priority of -99, which is lower (meaning higher
  precedence) than nixos-nat which is -100. This results in forwarded ports bypassing other host
  firewall rules. You can view this configuration with these commands:

```sh
$ nft -y list table ip io.systemd.nat
# Prints port forwarding mappings, NAT masquerade config, and filter chains.

$ nft -y list table ip6 io.systemd.nat
# Same as above but for IPv6
```
