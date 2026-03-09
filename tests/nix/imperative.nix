{ pkgs, lib, self, ... }: let
  mkContainer = name: modules: (self.lib.mkContainer {
    inherit pkgs name;
    inherit (pkgs) system;
    nixpkgs = pkgs.path;
    modules = [{ system.stateVersion = "25.11"; }] ++ modules;
  });

  emptyContainer = (self.lib.mkContainer {
    inherit pkgs;
    inherit (pkgs) system;
    nixpkgs = pkgs.path;
    name = "foo";
    modules = [{ system.stateVersion = "25.11"; }];
  });

  helloContainer = self.lib.mkContainer {
    inherit pkgs;
    inherit (pkgs) system;
    nixpkgs = pkgs.path;
    name = "foo";
    modules = [
      { system.stateVersion = "25.11"; }
      ({ pkgs, ... }: {
        environment.systemPackages = [ pkgs.hello ];
      })
    ];
  };

  nginxContainer = self.lib.mkContainer {
    inherit pkgs;
    inherit (pkgs) system;
    nixpkgs = pkgs.path;
    name = "foonet";
    modules = [
      { system.stateVersion = "25.11"; }
      ({ pkgs, ... }: {
        services.nginx.enable = true;
        services.nginx.virtualHosts.localhost.default = true;
        networking.firewall.allowedTCPPorts = [ 80 ];
      })
    ];
  };

  nginxContainerZone = self.lib.mkContainer {
    inherit pkgs;
    inherit (pkgs) system;
    nixpkgs = pkgs.path;
    name = "foozone";
    modules = [
      { system.stateVersion = "25.11"; }
      ({ pkgs, ... }: {
        services.nginx.enable = true;
        networking.firewall.allowedTCPPorts = [ 80 ];
        nixosContainer.zone = "foo";
      })
    ];
  };

  nginxContainerZone2 = self.lib.mkContainer {
    inherit pkgs;
    inherit (pkgs) system;
    nixpkgs = pkgs.path;
    name = "foozone2";
    modules = [
      { system.stateVersion = "25.11"; }
      ({ pkgs, ... }: {
        environment.systemPackages = [ pkgs.hello ];
        nixosContainer.zone = "foo2";
      })
    ];
  };

  nginxContainerNet = self.lib.mkContainer {
    inherit pkgs;
    inherit (pkgs) system;
    nixpkgs = pkgs.path;
    name = "foonet2";
    modules = [
      { system.stateVersion = "25.11"; }
      ({ pkgs, ... }: {
        nixosContainer.network.v4.static = {
          containerPool = [ "10.42.42.2/24" ];
          hostAddresses = [
            "10.42.42.1/24"
          ];
        };
      })
    ];
  };
in {
  name = "nspawn-imperative";

  nodes =
    let
      base = { config, pkgs, ... }: {
        # Needed to make sure that the DHCPServer of `systemd-networkd' properly works and
        # can assign IPv4 addresses to containers.
        time.timeZone = "Europe/Berlin";
        networking.firewall.allowedUDPPorts = [ 53 67 68 546 547 ];
        environment.systemPackages = [ pkgs.jq pkgs.nixos-nspawn ];
        nix.nixPath = [ "nixpkgs=${pkgs.path}" ];
        nix.settings.sandbox = false;
        nix.settings.substituters = lib.mkForce [ ]; # don't try to access cache.nixos.org
        virtualisation.memorySize = 4096;
        virtualisation.writableStore = true;
        system.extraDependencies = [ pkgs.hello ];

        networking = {
          useDHCP = false;
          interfaces.eth0.useDHCP = true;
          interfaces.eth1.useDHCP = true;
        };

        # from containers-imperative.nix
        virtualisation.additionalPaths =
          let
            emptyContainer = self.lib.mkContainer {
              inherit pkgs;
              inherit (pkgs) system;
              nixpkgs = pkgs.path;
              name = "bar";
              modules = [
                ({ pkgs, ... }: {
                  environment.systemPackages = [ pkgs.hello ];
                })
              ];
            };
          in
          with pkgs; [
            perl538Packages.Env
            hello
            bash
            bash.debug
            perl538Packages.ConfigIniFiles
            perl538
            gcc13
            stdenv
            stdenvNoCC
            emptyContainer
            libxslt
            desktop-file-utils
            texinfo
            docbook5
            libxml2
            docbook_xsl_ns
            xorg.lndir
            documentation-highlighter
            nixos-nspawn
            sudo-nspawn
            nginxStable
            coreutils
            gixy
            mailcap
          ];
      };
    in
    {
      imperativeanddeclarative = { pkgs, ... }: {
        imports = [ base ];
        nixos.containers.instances.bar = {
          system-config.environment.systemPackages = [ pkgs.hello ];
          zone = "foo";
        };

        nixos.containers.zones = {
          foo.hostAddresses = [ "10.100.200.1/24" ];
        };
      };
      onlyimperative = { pkgs, ... }: {
        imports = [ base ];
      };
    };

  testScript =
    let
      empty = pkgs.writeText "empty.nix" ''{
  }'';
    in
    ''
      start_all()

      def create_container(vm):
          print(vm.succeed(
            "nixos-nspawn -v create foo --config ${pkgs.writeText "foo.nix" ''
              { pkgs, ... }: {
                environment.systemPackages = [ pkgs.hello ];
              }
            ''}"
          ))

      onlyimperative.wait_for_unit("multi-user.target")
      imperativeanddeclarative.wait_for_unit("multi-user.target")
      imperativeanddeclarative.wait_for_unit("machines.target")

      with subtest("Interactions with nixos-nspawn"):
          onlyimperative.succeed("nixos-nspawn list --json | grep -i '\\[\\]'")
          create_container(onlyimperative)

          onlyimperative.succeed("test 1 = \"$(nixos-nspawn list --json | jq 'length')\"")

          onlyimperative.succeed("test 1 = \"$(nixos-nspawn list-generations --json foo | jq 'length')\"")

          imperativeanddeclarative.succeed("nixos-nspawn list --type imperative --json | grep -i '\\[\\]'")
          imperativeanddeclarative.fail("nixos-nspawn list-generations bar")
          create_container(imperativeanddeclarative)
          imperativeanddeclarative.succeed("test 2 = \"$(nixos-nspawn list --json | jq 'length')\"")
          imperativeanddeclarative.succeed("test 1 = \"$(nixos-nspawn list --type imperative --json | jq 'length')\"")

      with subtest("Backtraces / error handling"):
          out = onlyimperative.fail(
              "nixos-nspawn --verbose create bar --config ${pkgs.writeText "bar.nix" ''
                {
                  nixosContainer.sharedNix = false;
                }
              ''} 2>&1"
          )

          # expect python backtrace
          assert "manager.py" in out
          # expect nix backtrace
          assert "while evaluating derivation 'bar'" in out
          # expect actual error
          assert "Experimental 'sharedNix'-feature isn't supported for imperative containers!" in out

          onlyimperative.succeed(
              "nixos-nspawn create bar --config ${empty}"
          )

      with subtest("Update / Rollback"):
          out = onlyimperative.fail(
              "nixos-nspawn 2>&1 create bar23 --config ${pkgs.writeText "bar23.nix" ''
                {
                  nixosContainer.activation.strategy = "dynamic";
                }
              ''}"
          )

          assert "'dynamic' is currently not supported" in out
          onlyimperative.succeed("systemd-run -M foo --pty --quiet /bin/sh --login -c 'hello'")

          # Try removing the package we added
          out = onlyimperative.succeed(
              "nixos-nspawn update 2>&1 foo --strategy reload --config ${pkgs.writeText "foo2.nix" ''{
              }''}"
          )

          print(out)

          assert "Reloading" in out

          onlyimperative.fail(
              "systemd-run -M foo --pty --quiet /bin/sh --login -c 'hello'"
          )

          onlyimperative.succeed("test 2 = \"$(nixos-nspawn list-generations --json foo | jq 'length')\"")
          # TODO reimplement strategy for rollback
          onlyimperative.succeed("nixos-nspawn rollback foo")

          onlyimperative.wait_until_succeeds("systemctl -M foo is-active multi-user.target")
          onlyimperative.succeed("systemd-run -M foo --pty /bin/sh --login -c 'hello'")

          # Existing container cannot be re-created
          onlyimperative.fail(
              "nixos-nspawn create foo --config ${empty}"
          )

      with subtest("Networking"):
          # Container is in the host network-namespace by default, so no own IP.
          # FIXME find out if this has changed and what we should do here.
          #onlyimperative.fail("ping -c4 foo >&2")
          out = onlyimperative.succeed(
              "nixos-nspawn create foonet --config ${pkgs.writeText "foo2.nix" ''
                { pkgs, ... }: {
                  services.nginx.enable = true;
                  services.nginx.virtualHosts.localhost.default = true;
                  networking.firewall.allowedTCPPorts = [ 80 ];
                }
              ''}"
          )

          # RFC1918 private IP assigned via DHCP
          onlyimperative.wait_until_succeeds("ping -c4 foonet")
          print(onlyimperative.execute("systemctl -M foonet status nginx"))

          onlyimperative.succeed("curl --fail -i >&2 foonet:80")

          # Proper cleanup
          onlyimperative.succeed("nixos-nspawn remove foonet")
          onlyimperative.wait_until_fails("ping -c4 foonet")
          onlyimperative.fail("test -e /etc/systemd/nspawn/foonet.nspawn")

          imperativeanddeclarative.succeed(
              "nixos-nspawn create foozone --config ${pkgs.writeText "foo2.nix" ''
                { pkgs, ... }: {
                  services.nginx.enable = true;
                  networking.firewall.allowedTCPPorts = [ 80 ];
                  nixosContainer.zone = "foo";
                }
              ''}"
          )

          imperativeanddeclarative.wait_until_succeeds("ip a s vb-foozone")
          imperativeanddeclarative.fail("ip a s ve-foozone")

          # Don't start a container if zone does not exist
          imperativeanddeclarative.fail(
              "nixos-nspawn create foozone2 --config ${pkgs.writeText "foo2.nix" ''
                { pkgs, ... }: {
                  nixosContainer.zone = "foo2";
                }
              ''}"
          )

      with subtest("Removal"):
          onlyimperative.succeed("nixos-nspawn remove foo")
          onlyimperative.fail("systemd-run -M foo --pty --quiet /bin/sh --login -c 'hello'")
          onlyimperative.fail("test -e /etc/systemd/nspawn/foo.nspawn")

      with subtest("Static networking"):
          onlyimperative.succeed(
              "nixos-nspawn create foonet2 --config ${pkgs.writeText "foonet2.nix" ''
                {
                  nixosContainer.network.v4.static = {
                    containerPool = [ "10.42.42.2/24" ];
                    hostAddresses = [
                      "10.42.42.1/24"
                    ];
                  };
                }
              ''}"
          )

          onlyimperative.wait_until_succeeds("ping >&2 -c4 10.42.42.2")
          onlyimperative.succeed("machinectl status foonet2 | grep 10.42.42.2")

      with subtest("Reboot via machinectl(1)"):
          onlyimperative.succeed("machinectl poweroff foonet2")
          onlyimperative.wait_until_fails("ping >&2 -c4 10.42.42.2")
          onlyimperative.succeed("machinectl start foonet2")
          onlyimperative.wait_until_succeeds("ping >&2 -c4 10.42.42.2")

      onlyimperative.shutdown()
      imperativeanddeclarative.shutdown()
    '';
}
