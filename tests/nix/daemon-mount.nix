{ pkgs, lib, ... }:
{
  name = "containers-next-daemon-mount";

  nodes.machine = {
    nixos.containers.instances.container0 = {
      mountDaemonSocket = true;
      bindMounts = [
        "/tmp"
      ];
      config =
        { pkgs, ... }:
        {
          environment.systemPackages = [
            (pkgs.writeShellScriptBin "run-build" ''
              set -ex

              i=0
              while ! nix-build ${pkgs.writeText "test.nix" ''
                builtins.derivation {
                  name = "trivial";
                  system = "${pkgs.stdenv.hostPlatform.system}";
                  builder = "/bin/sh";
                  allowSubstitutes = false;
                  preferLocalBuild = true;
                  args = ["-c" "echo success > $out; exit 0"];
                }
              ''} && [[ "$i" -le 3 ]]; do
                sleep 3
                i=$((i+1))
              done

              test -f result
              grep success result
            '')
          ];
          systemd.sockets.nix-daemon.unitConfig.ConditionPathExists = [
            "!/nix/var/nix/daemon-socket/socket"
          ];
          # Need to signal to the host that the container is ready
          systemd.services.ready-signal = {
            wantedBy = [ "multi-user.target" ];
            after = [ "multi-user.target" ];
            script = "touch /tmp/ready";
          };
        };
    };
  };

  testScript = ''
    start_all()

    machine.wait_for_unit("machines.target")
    machine.wait_for_unit("nix-daemon.socket")

    machine.succeed("while [[ ! -e /tmp/ready ]]; do sleep 1; done")

    machine.succeed(
      "systemd-run -M container0 --pty --quiet -- /bin/sh --login -c 'run-build'"
    )

    machine.shutdown()
  '';
}
