{
  self,
  config,
  pkgs,
  ...
}:
{
  name = "simple-nspawn-use";

  nodes.server =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    {
      nixos.containers.instances.simple.system-config = {
        services.nginx = {
          enable = true;
          virtualHosts.localhost.default = true;
        };
        networking.firewall.allowedTCPPorts = [ 80 ];
      };

      specialisation.reload.configuration = {
        nixos.containers.instances.simple.system-config = {
          services.openssh.enable = true;
          networking.firewall.allowedTCPPorts = [ 22 ];
        };
      };

      specialisation.restart.configuration = {
        nixos.containers.instances.simple.bindMounts = [
          "/tmp:/mount"
        ];
      };
    };

  testScript =
    { nodes, ... }:
    let
      switchTo =
        sp: "${nodes.server.system.build.toplevel}/specialisation/${sp}/bin/switch-to-configuration test";
    in
    ''
      import time

      def wait_until_stopped(machine, unit: str) -> None:
        while True:
          info = machine.get_unit_info(unit)
          if info.get("ActiveState") == "inactive":
            return
          time.sleep(1)

      def assert_action(switch_info: list[str], action: str) -> None:
          assert any(
            action in line and "systemd-nspawn@simple.service" in line
            for line in switch_info
          ), f"The instance was not {action}"

      start_all()

      server.wait_for_unit("machines.target")
      server.wait_for_unit("multi-user.target")
      server.wait_for_unit("network.target")
      server.wait_for_unit("systemd-nspawn@simple.service")
      server.wait_for_unit("network.target")

      with subtest("Container up and running"):
          # Resolution provided by nss-mymachines
          server.wait_until_succeeds("ping -I ve-simple -6 simple -c3 >&2", timeout=30)
          server.wait_until_succeeds("ping -4 simple -c3 >&2", timeout=30)
          server.wait_until_succeeds("curl -4 -o- -v http://simple | tee /dev/stderr | grep -i 'Welcome to nginx'", timeout=30)

      with subtest("Container config change"):
          switch_info = server.succeed("${switchTo "reload"} 2>&1 | tee /dev/stderr").splitlines()
          assert_action(switch_info, "reloading")
          server.wait_until_succeeds("nc -z simple 22", timeout=30)

      with subtest("Container mounts change"):
          server.succeed("touch /tmp/something")
          switch_info = server.succeed("${switchTo "restart"} 2>&1 | tee /dev/stderr").splitlines()
          assert_action(switch_info, "stopping")
          assert_action(switch_info, "starting")
          server.succeed("machinectl shell simple $(which stat) /mount/something")

      with subtest("Container shutdown"):
          server.succeed("systemctl stop systemd-nspawn@simple.service")
          wait_until_stopped(server, "systemd-nspawn@simple.service")
          server.fail("ping -4 simple -c3 >&2")

      server.shutdown()
    '';
}
