{ pkgs, lib, config, ... }:
let
  sudo-nspawn' = import ../sudo-nspawn.nix { inherit (pkgs) sudo; };
  sudo-nspawn = if pkgs ? "sudo-nspawn" then pkgs.sudo-nspawn else sudo-nspawn';
in
{
  boot.isContainer = true;

  users.mutableUsers = false;
  users.allowNoPasswordLogin = true;

  # We need a static libsudoers if we bind-mount into a user-namespaced
  # container since the bind-mounts are owned by `nouser:nogroup` then (including
  # `/nix/store`) and this doesn't like sudo.
  security.sudo.package = lib.mkDefault sudo-nspawn;

  # Containers are supposed to use systemd-networkd to have a proper
  # networking stack even during boot-up.
  networking = {
    useHostResolvConf = false;
    useDHCP = false;
    useNetworkd = true;
  };

  # Configure the container's network interface
  systemd.network.networks."20-host0" = {
    matchConfig = {
      Virtualization = "container";
      Name = "host0";
    };
    dhcpConfig.UseTimezone = true;
    networkConfig = {
      DHCP = lib.mkDefault true;
      LLDP = true;
      EmitLLDP = "customer-bridge";
      LinkLocalAddressing = lib.mkDefault "ipv6";
    };
  };

  # Fix for infinite recursion during build.
  # See https://github.com/NixOS/nixpkgs/issues/353225
  networking.resolvconf.enable = false;

  # When mountDaemonSocket is enabled, the in-container daemon needs to not start.
  # Block the socket startup if the socket file already exists on boot.
  systemd.sockets.nix-daemon.unitConfig.ConditionPathExists = [
    "!/nix/var/nix/daemon-socket/socket"
  ];
}
