{ self, pkgs, lib, ... }:
{
  name = "containers-next-nat";

  nodes.client = {
    systemd.network.networks."10-eth1" = {
      matchConfig.Name = "eth1";
      address = [ "fd23::1/64" "192.168.1.1/24" ];
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

  nodes.host = {
    systemd.network.networks."10-eth1" = {
      matchConfig.Name = "eth1";
      address = [ "fd24::1/64" "192.168.1.2/24" ];
      networkConfig.IPv4Forwarding = "yes";
      networkConfig.IPv6Forwarding = "yes";
      routes = [
        { Destination = "fd23::1/64"; }
      ];
    };

    networking.firewall.allowedUDPPorts = [ 53 67 68 546 547 ];
    networking.firewall.logRefusedPackets = true;

    nixos.containers.instances = with lib; mapAttrs
      (const (nat: {
        network = lib.genAttrs [ "v4" "v6" ] (const { inherit nat; });
      }))
      {
        withnat = true;
        nonat = false;
      };
  };

  testScript = let
    ping = "$(which ping) -W1 -c2 >&2";
  in ''
    start_all()

    host.wait_for_unit("network.target")
    host.wait_for_unit("machines.target")
    client.wait_for_unit("network.target")

    with subtest("Confirm connectivity between host & client (precondition)"):
        host.succeed("${ping} 192.168.1.1")
        client.succeed("${ping} 192.168.1.2")
        host.succeed("${ping} fd23::1")
        client.succeed("${ping} fd24::1")

    with subtest("Confirm NAT"):
        # Wait for the withnat VM to be routable
        host.wait_until_succeeds("${ping} -4 withnat")
        host.wait_until_succeeds("${ping} -6 withnat")
        host.succeed("systemd-run -M withnat --pty -- ${ping} 192.168.1.1")
        host.fail("systemd-run -M nonat --pty -- ${ping} 192.168.1.1")
        host.succeed("systemd-run -M withnat --pty -- ${ping} fd23::1")
        host.fail("systemd-run -M nonat --pty -- ${ping} fd23::1")

    host.shutdown()
    client.shutdown()
  '';
}
