{ self, lib, ... }:
let
  instances.dynamic = {
    activation.strategy = "dynamic";
  };

  instances.teststop = { };

  instances.restart = {
    activation.strategy = "restart";
  };

  instances.reload = {
    activation.strategy = "reload";
  };

  instances.none = {
    activation.strategy = "none";
  };

  instances.dynamic2 = {
    activation.strategy = "dynamic";
  };

  instances.static = {
    activation.strategy = "dynamic";
    zone = "foo";
  };
in
{
  name = "container-tests";

  nodes = {
    machine =
      { ... }:
      {
        nixos.containers = {
          zones.foo = {
            address = [
              ""
              "10.231.142.1/24"
            ];
          };
        };

        specialisation = rec {
          initial.configuration = {
            nixos.containers.instances = instances;
          };
          configchange.configuration =
            { lib, pkgs, ... }:
            {
              nixos.containers.instances = lib.mkMerge [
                (lib.filterAttrs (name: lib.const (name != "teststop")) instances)
                {
                  dynamic.system-config = {
                    services.nginx = {
                      enable = true;
                      virtualHosts."localhost" = {
                        listen = [
                          {
                            addr = "0.0.0.0";
                            port = 80;
                            ssl = false;
                          }
                        ];
                      };
                    };
                    networking.firewall.allowedTCPPorts = [ 80 ];
                  };
                }
                {
                  dynamic2.system-config = {
                    services.nginx.enable = true;
                  };
                }
                {
                  reload.system-config = {
                    services.nginx.enable = true;
                  };
                }
              ];

              # An out of band nspawn change should trigger restarts too.
              systemd.nspawn.restart.filesConfig.BindReadOnly = [ "/etc:/foo" ];
            };
          configchange2.configuration =
            { lib, pkgs, ... }:
            {
              imports = [ configchange.configuration ];
              systemd.nspawn.dynamic.filesConfig.BindReadOnly = [ "/etc:/foo" ];
              nixos.containers.instances = lib.mkMerge [
                (lib.filterAttrs (name: lib.const (name != "teststop")) instances)
                {
                  new = { };
                  restart.system-config.users.groups.nixtest = { };
                }
              ];
            };
        };
      };
  };

  testScript =
    { nodes, ... }:
    let
      switchTo =
        sp: "${nodes.machine.system.build.toplevel}/specialisation/${sp}/bin/switch-to-configuration test";
    in
    ''
      from typing import Dict, List
      machine.start()
      machine.wait_for_unit("network.target")
      machine.wait_for_unit("machines.target")
      machine.wait_for_unit("multi-user.target")

      with subtest("Initial state"):
          machine.succeed(
              "${switchTo "initial"} 2>&1 | tee /dev/stderr"
          )
          machine.wait_for_unit("machines.target")
          available = machine.succeed("machinectl")
          for i in ['dynamic', 'teststop', 'restart', 'reload', 'none', 'dynamic2', 'static']:
              assert i in available, f"Expected machine {i} in `machinectl output!"
              machine.wait_until_succeeds(f"ping -4 -c2 {i} >&2")

          machine.fail("curl dynamic -sSf --connect-timeout 10")

          machine.succeed("systemd-run -M static --pty --quiet -- /bin/sh --login -c 'networkctl | grep host0 | grep configured'")

          for m in ['reload', 'restart']:
              machine.fail(
                  f"systemd-run -M {m} --pty --quiet -- /bin/sh --login -c 'test -e /foo/systemd'"
              )

      with subtest("Activate changes"):
          machine.succeed("machinectl stop dynamic2")
          act_output = machine.succeed(
              "${switchTo "configchange"} 2>&1 | tee /dev/stderr"
          ).split('\n')
          machine.succeed("sleep 10")

          units: Dict[str, List[str]] = {}
          for state in ['stopping', 'starting', 'restarting', 'reloading']:
              units[state] = []
              outline = f"{state} the following units: "
              for line in act_output:
                  if line.startswith(outline):
                      units[state] = line.replace(outline, "").split(', ')
                      break

          print(units)
          assert "systemd-nspawn@reload.service" in units['reloading']
          assert "systemd-nspawn@reload.service" not in units['restarting']

          assert "systemd-nspawn@dynamic2.service" not in units['reloading']
          assert "systemd-nspawn@dynamic2.service" not in units['restarting']

          assert "systemd-nspawn@restart.service" in units['stopping']
          assert "systemd-nspawn@restart.service" in units['starting']

          assert "systemd-nspawn@dynamic.service" in units['reloading']
          assert "systemd-nspawn@dynamic.service" not in units['restarting']

          assert "systemd-nspawn@reload.service" not in units['starting']
          assert "systemd-nspawn@teststop.service" in units['stopping']
          assert "systemd-nspawn@none.service" not in act_output

      with subtest("Check for successful activation"):
          machine.wait_until_succeeds("curl dynamic -sSf --connect-timeout 10")
          machine.fail("ping -4 -c3 teststop -c3")

          machine.wait_until_succeeds("ping -4 -c3 restart >&2")
          machine.succeed(
              "systemd-run -M restart --pty --quiet -- /bin/sh --login -c 'test -e /foo/systemd'"
          )

          # A reload is forced for this machine, but a reload doesn't refresh bind mounts.
          machine.fail(
              "systemd-run -M reload --pty --quiet -- /bin/sh --login -c 'test -e /foo/systemd'"
          )

      with subtest("More changes"):
          machine.succeed(
              "${switchTo "configchange2"} 2>&1 | tee /dev/stderr"
          )

          machine.wait_until_succeeds("ping -4 -c3 dynamic >&2")

          machine.succeed(
              "systemd-run -M dynamic --pty --quiet -- /bin/sh --login -c 'test -e /foo/systemd'"
          )

          machine.wait_until_succeeds("ping -4 -c3 new >&2")

      machine.shutdown()
    '';
}
