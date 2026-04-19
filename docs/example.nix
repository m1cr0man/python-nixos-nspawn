{
  system.stateVersion = "26.05";

  # Configure a basic web server. HTTP only, no TLS.
  services.nginx = {
    enable = true;
    virtualHosts.localhost.default = true;
  };
  networking.firewall.allowedTCPPorts = [ 80 ];

  # Expose the port to the internet
  # *IMPORTANT:* Even if your firewall would usually block this,
  # systemd-nspawn will configure nftables such that it will
  # work anyway.
  nixosContainer.forwardPorts = [
    {
      hostPort = 8181;
      containerPort = 80;
    }
  ];
  nixosContainer.hostNetworkConfig.ipv6Prefixes = [
    {
      Prefix = "fd12::/64";
      Assign = true;
    }
  ];
  nixosContainer.containerNetworkConfig = {
    address = [ "fd12::2/64" ];
    dhcpV6Config.UseAddress = false;
  };
}
