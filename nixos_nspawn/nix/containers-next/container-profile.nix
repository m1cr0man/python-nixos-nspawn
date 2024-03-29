{ pkgs, lib, ... }:
let
  sudo-nspawn = import ../sudo-nspawn.nix { inherit (pkgs) sudo; };
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
}
