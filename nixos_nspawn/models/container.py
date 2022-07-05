from json import load
from logging import getLogger
from os import getenv
from pathlib import Path
from shutil import rmtree
from time import sleep
from typing import Any, Optional, Union

from ..constants import (
    DEFAULT_EVAL_SCRIPT,
    FLAKE_KEY,
    MACHINE_STATE_DIR,
    NIX_PROFILE_DIR,
    NSENTER_ARGS,
)
from ..utilities import CommandError, SystemdUnitParser, run_command
from ._printable import Printable
from .nix_generation import NixGeneration


class ContainerError(BaseException):
    ...


class Container(Printable):
    unit_file: Path
    __profile_data: Optional[dict] = None
    __unit_parser: Optional[SystemdUnitParser] = None

    def __init__(self, unit_file: Path) -> None:
        self.unit_file = unit_file

        self.name = self.unit_file.name[: -len(".nspawn")]

        self.__logger = getLogger(f"nixos_nspawn.container.{self.name}")
        self.__state_dir = MACHINE_STATE_DIR / self.name
        self.__profile_dir = NIX_PROFILE_DIR / self.name
        self.__nix_path = self.__profile_dir / "system"
        self.__network_unit_file = (
            self.unit_file.parent.parent / "network" / f"20-ve-{self.name}.network"
        )

        super(Container, self).__init__()

    def __eq__(self, other: Union["Container", Any]) -> bool:
        return isinstance(other, Container) and self.unit_file == other.unit_file

    @property
    def _unit_parser(self) -> SystemdUnitParser:
        # Defined as a property since we create Container objects
        # during new container creation before the unit_file exists.
        if not self.__unit_parser:
            parser = SystemdUnitParser()
            self.__logger.debug("Parsing %s", self.unit_file)
            parser.read(self.unit_file)
            self.__unit_parser = parser

        return self.__unit_parser

    @property
    def is_imperative(self) -> bool:
        return self._unit_parser.getboolean("Exec", "X-Imperative", fallback=False)

    @property
    def profile_data(self) -> dict:
        if not self.__profile_data:
            self.__logger.debug("Loading %s", self.__nix_path / "data")
            with (self.__nix_path / "data").open() as profile_data_fd:
                self.__profile_data = load(profile_data_fd)

        return self.__profile_data

    @property
    def activation_strategy(self) -> str:
        return self.profile_data["activation"]["strategy"]

    @property
    def state(self) -> str:
        return self.get_runtime_property("State", ignore_error=True) or "powered off"

    @classmethod
    def from_unit_file(cls, unit_file: Path) -> "Container":
        return cls(unit_file)

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "unit_file": self.unit_file,
            "is_imperative": self.is_imperative,
        }

    def render(self) -> str:
        return "\n".join(
            (
                f"Container [bold]{self.name}[/bold]",
                f"  [bold]Unit File:[/bold] {self.unit_file}",
                f"  [bold]Imperative:[/bold] {self.is_imperative}",
                f"  [bold]State:[/bold] {self.state}",
            )
        )

    def _create_profile_directory(self) -> None:
        # If it already exists, that's a problem. This is a new container.
        if self.__profile_dir.exists():
            raise ContainerError(
                f"Profile for {self.name} already exists!"
                " Perhaps some dirty state? Try removing with the 'remove' command."
            )
        self.__profile_dir.mkdir(mode=0o755, parents=True)
        self.__profile_dir.chmod(mode=0o755)

    def build_nixos_config(
        self, config: Path, update: bool = False, show_trace: bool = False
    ) -> Path:
        # Create the profile directory if necessary
        if not update:
            self._create_profile_directory()

        self.__logger.info("Building configuration from '%s'", config)
        eval_code = getenv("NIXOS_NSPAWN_EVAL", str(DEFAULT_EVAL_SCRIPT))
        nixpkgs = getenv("NIXOS_NSPAWN_NIXPKGS", "<nixpkgs>")
        args = [
            "nix-env",
            "-f",
            eval_code,
            "-p",
            str(self.__nix_path),
            "--arg",
            "nixpkgs",
            nixpkgs,
            "--arg",
            "config",
            str(config),
            "--set",
        ]
        if show_trace:
            args.append("--show-trace")

        run_command(args)

        return self.__nix_path

    def build_flake_config(
        self, flake: str, update: bool = False, show_trace: bool = False
    ) -> Path:
        # Create the profile directory if necessary
        if not update:
            self._create_profile_directory()

        # Same thing as nixos-rebuild. Prepend our own key in the flake.
        flake_split = flake.split("#")
        if len(flake_split) != 2:
            raise ContainerError(f"'{flake}' is not a valid flake path.")

        flake_src, flake_attr = flake_split
        if FLAKE_KEY not in flake_attr:
            flake_attr = f"{FLAKE_KEY}.{flake_attr}"

        self.__logger.info("Building configuration from flake %s", flake)
        args = [
            "nix",
            "build",
            "--no-link",
            "--profile",
            str(self.__nix_path),
            f"{flake_src}#{flake_attr}",
        ]

        if show_trace:
            args.append("--show-trace")

        run_command(args)

        return self.__nix_path

    def _write_network_unit_file(self) -> None:
        self.__logger.debug("Writing network unit file")
        unit_parser = SystemdUnitParser()
        profile_data = self.profile_data

        # [Match]
        unit_parser.add_section("Match")
        match_section = unit_parser["Match"]
        match_section["Driver"] = "veth"
        match_section["Name"] = f"ve-{self.name}"

        # [Network]
        unit_parser.add_section("Network")
        network_section = unit_parser["Network"]
        network_section["DHCPServer"] = "yes"
        network_section["EmitLLDP"] = "customer-bridge"
        network_section["IPForward"] = "yes"
        network_section["LLDP"] = "yes"

        if profile_data["network"]["v4"]["nat"]:
            network_section["IPMasquerade"] = "both"

        if profile_data["network"]["v6"]["addrPool"] != []:
            self.__logger.warn(
                "Warning: IPv6 SLAAC currently not supported for imperative containers!"
            )

        # Check all possible network configurations for addresses
        for ips in [
            profile_data["network"]["v4"]["addrPool"],
            profile_data["network"]["v6"]["addrPool"],
            profile_data["network"]["v4"]["static"]["hostAddresses"],
            profile_data["network"]["v6"]["static"]["hostAddresses"],
        ]:
            for ip in ips:
                network_section["Address"] = ip

        self.__network_unit_file.parent.mkdir(mode=0o755, exist_ok=True)
        self.__network_unit_file.parent.chmod(mode=0o755)
        with self.__network_unit_file.open("w+") as unit_fd:
            unit_parser.write(unit_fd, space_around_delimiters=False)
        self.__network_unit_file.chmod(0o644)

        run_command(["systemctl", "restart", "systemd-networkd"])

    def write_nspawn_unit_file(self) -> None:
        self.__logger.info("Writing nspawn unit file")
        unit_parser = SystemdUnitParser()
        profile_data = self.profile_data

        # [Exec]
        unit_parser.add_section("Exec")
        exec_section = unit_parser["Exec"]
        exec_section["Boot"] = "false"
        exec_section["Parameters"] = str(self.__nix_path / "init")
        exec_section["PrivateUsers"] = "yes"
        exec_section["X-ActivationStrategy"] = self.activation_strategy
        exec_section["X-Imperative"] = "1"

        if profile_data.get("ephemeral"):
            exec_section["Ephemeral"] = "true"
            exec_section["LinkJournal"] = "auto"
        else:
            exec_section["LinkJournal"] = "guest"

        # [Files]
        unit_parser.add_section("Files")
        files_section = unit_parser["Files"]
        files_section["BindReadOnly"] = "/nix/store"
        files_section["BindReadOnly"] = "/nix/var/nix/db"
        files_section["BindReadOnly"] = "/nix/var/nix/profiles"
        files_section["BindReadOnly"] = str(NIX_PROFILE_DIR)
        files_section["PrivateUsersOwnership"] = "auto"

        for mountpoint in profile_data.get("bindMounts", []):
            files_section["Bind"] = mountpoint

        # [Network]
        unit_parser.add_section("Network")
        network_section = unit_parser["Network"]

        if network := profile_data.get("network"):
            network_section["Private"] = "true"
            network_section["VirtualEthernet"] = "true"

        if zone := profile_data.get("zone"):
            network_section["Zone"] = zone

        if bridge := profile_data.get("bridge"):
            network_section["Bridge"] = bridge

        if network and not zone:
            self._write_network_unit_file()

        for forward_port in profile_data.get("forwardPorts", []):
            network_section["Port"] = forward_port

        self.unit_file.parent.mkdir(mode=0o755, exist_ok=True)
        self.unit_file.parent.chmod(mode=0o755)
        with self.unit_file.open("w+") as unit_fd:
            unit_parser.write(unit_fd, space_around_delimiters=False)
        self.unit_file.chmod(0o644)

    def create_state_directories(self) -> None:
        self.__logger.debug("Creating state directories")
        etc = self.__state_dir / "etc"
        etc.mkdir(mode=0o755, parents=True, exist_ok=True)
        self.__state_dir.chmod(mode=0o755)
        etc.chmod(mode=0o755)
        (etc / "os-release").touch(mode=0o644, exist_ok=True)

    def get_runtime_property(self, key: str, ignore_error: bool = False) -> str:
        self.__logger.debug("Reading runtime property '%s'", key)
        try:
            rc, stdout = run_command(
                ["machinectl", "show", self.name, "--property", key, "--value"], capture_stdout=True
            )
            self.__logger.debug("Value of runtime property %s: '%s'", key, stdout)
            return stdout
        except CommandError as err:
            if ignore_error:
                return ""
            raise err

    def run_command(self, args: list[str], capture_stdout: bool = False) -> tuple[int, str]:
        """Runs a command within the container"""
        leader_pid = self.get_runtime_property("Leader").strip()
        self.__logger.info("Running command '%s'", " ".join(args))
        return run_command(
            ["nsenter", "-t", leader_pid, *NSENTER_ARGS, "--", *args], capture_stdout=capture_stdout
        )

    def start(self) -> None:
        self.__logger.info("Starting")
        run_command(["machinectl", "start", self.name])

    def reboot(self) -> None:
        self.__logger.info("Rebooting")
        run_command(["machinectl", "reboot", self.name])

    def poweroff(self, wait: int = 10) -> None:
        self.__logger.info("Powering off")
        run_command(["machinectl", "poweroff", self.name])
        while wait > 0 and self.state != "powered off":
            wait -= 1
            sleep(1)

    def reload(self) -> None:
        self.__logger.info("Reloading")
        switcher = self.__nix_path / "bin" / "switch-to-configuration"
        self.run_command([str(switcher), "test"])

    def rollback(self) -> None:
        self.__logger.info("Rolling back")
        run_command(["nix-env", "-p", str(self.__nix_path), "--rollback"])

    def get_generations(self) -> list[NixGeneration]:
        rc, stdout = run_command(
            ["nix-env", "-p", str(self.__nix_path), "--list-generations"], capture_stdout=True
        )
        return [NixGeneration.from_list_output(gen) for gen in stdout.split("\n")]

    def activate_config(self, strategy: Optional[str] = None) -> None:
        self.__logger.info("Activating configuration. Strategy override: %s", strategy)
        if strategy is None:
            strategy = self.activation_strategy

        self.__logger.debug("Using activation strategy [bold]%s[/bold]", strategy)
        if strategy.lower().strip() == "restart":
            self.reboot()
        else:
            self.reload()

    def destroy(self) -> None:
        """Removes all files associated with the contanier."""
        self.__logger.info("Destroying files")
        if self.__profile_dir.exists():
            rmtree(str(self.__profile_dir))
        if self.__state_dir.exists():
            # Ensure /var/empty can be deleted by removing the immutable bit
            empty_dir = self.__state_dir / "var" / "empty"
            if empty_dir.exists():
                run_command(["chattr", "-i", str(empty_dir)])
            rmtree(str(self.__state_dir))
        self.__network_unit_file.unlink(missing_ok=True)
        self.unit_file.unlink(missing_ok=True)
