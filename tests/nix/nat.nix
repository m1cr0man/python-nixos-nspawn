{
  self,
  pkgs,
  lib,
  ...
}:
{
  name = "containers-next-nat";

  nodes.client = {
    systemd.network.networks."10-eth1" = {
      matchConfig.Name = "eth1";
      address = [
        "fd23::1/64"
        "192.168.1.1/24"
      ];
      routes = [
        { Destination = "fd24::1/64"; }
      ];
    };

    # Check for NAT by making sure that only the host's addresses can ping
    # this machine.
    networking.firewall.extraCommands = ''
      iptables -A INPUT -p icmp -s 192.168.1.2 -j ACCEPT
      ip6tables -A INPUT -p icmp -s fd24::1 -j ACCEPT
      ip46tables -A INPUT -p icmp -j REJECT
    '';
    networking.firewall.logRefusedPackets = true;
  };

  nodes.server = {
    systemd.network.networks."10-eth1" = {
      matchConfig.Name = "eth1";
      address = [
        "fd24::1/64"
        "192.168.1.2/24"
      ];
      networkConfig.IPv4Forwarding = "yes";
      networkConfig.IPv6Forwarding = "yes";
      routes = [
        { Destination = "fd23::1/64"; }
      ];
    };

    networking.firewall.allowedUDPPorts = [
      53
      67
      68
      546
      547
    ];
    networking.firewall.logRefusedPackets = true;

    nixos.containers.instances = {
      withnat = {
        hostNetworkConfig.ipv6Prefixes = [
          {
            # Assign an IPv6 ULA
            Prefix = "fd00:c1::/64";
            Assign = true;
          }
        ];
      };
      nonat = {
        hostNetworkConfig.networkConfig.IPMasquerade = "no";
        hostNetworkConfig.ipv6Prefixes = [
          {
            # Assign an IPv6 ULA
            Prefix = "fd00:c2::/64";
            Assign = true;
          }
        ];
      };
    };
  };

  testScript =
    let
      ping = "$(which ping) -W1 -c2 >&2";
    in
    ''
      start_all()

      server.wait_for_unit("network.target")
      server.wait_for_unit("machines.target")
      client.wait_for_unit("network.target")

      with subtest("Confirm connectivity between host & client (precondition)"):
          server.succeed("${ping} 192.168.1.1")
          client.succeed("${ping} 192.168.1.2")
          server.succeed("${ping} fd23::1")
          client.succeed("${ping} fd24::1")

      with subtest("Confirm NAT"):
          # Wait for the withnat VM to be routable
          server.wait_until_succeeds("${ping} -4 withnat")
          server.wait_until_succeeds("${ping} -6 withnat")
          server.succeed("systemd-run -M withnat --pty -- ${ping} 192.168.1.1")
          server.fail("systemd-run -M nonat --pty -- ${ping} 192.168.1.1")
          server.succeed("systemd-run -M withnat --pty -- ${ping} fd23::1")
          server.fail("systemd-run -M nonat --pty -- ${ping} fd23::1")

      server.shutdown()
      client.shutdown()
    '';
}
