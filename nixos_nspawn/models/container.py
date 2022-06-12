from json import load
from os import getenv
from pathlib import Path
from shutil import rmtree
from typing import Any, Optional, Union

from ..constants import MACHINE_STATE_DIR, NIX_PROFILE_DIR, NSENTER_ARGS
from ..utilities import SystemdUnitParser, run_command
from ._printable import Printable
from .nix_generation import NixGeneration


class Container(Printable):
    unit_file: Path
    __profile_data: Optional[dict]

    def __init__(self, unit_file: Path) -> None:
        self.unit_file = unit_file

        self.name = self.unit_file.name[: -len(".nspawn")]

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
        # duration new container creation before the unit_file exists.
        if not self.__unit_parser:
            parser = SystemdUnitParser()
            parser.read(self.unit_file)
            self.__unit_parser = parser

        return self.__unit_parser

    @property
    def is_imperative(self) -> bool:
        return self._unit_parser.getboolean("Exec", "X-Imperative", fallback=False)

    @property
    def profile_data(self) -> dict:
        if not self.__profile_data:
            with (self.__nix_path / "data").open() as profile_data_fd:
                self.__profile_data = load(profile_data_fd)

        return self.__profile_data

    @property
    def activation_strategy(self) -> str:
        return self.profile_data["activation"]["strategy"]

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
                f"[bold]{self.name}[/bold]",
                f"  Unit File: {self.unit_file}",
            )
        )

    def build_nixos_config(
        self, config: Path, update: bool = False, show_trace: bool = False
    ) -> Path:
        # Create the profile directory if necessary
        if not update:
            # If it already exists, that's a problem. This is a new container.
            if self.__profile_dir.exists():
                raise Exception(
                    f"Profile for {self.name} already exists!"
                    " Perhaps some dirty state? Try removing with the 'remove' command."
                )
            self.__profile_dir.mkdir(mode=0o755, parents=True)

        eval_code = getenv("NIXOS_NSPAWN_EVAL", "@eval@")
        args = [
            "nix-env",
            "-p",
            str(self.__nix_path),
            "--arg",
            "config",
            str(config),
            "-f",
            eval_code,
            "--set",
            "--arg",
            "nixpkgs",
            "<nixpkgs>",
        ]
        if show_trace:
            args.append("--show-trace")

        run_command(args)

        return self.__nix_path

    def _write_network_unit_file(self) -> None:
        unit_parser = SystemdUnitParser()
        profile_data = self.profile_data

        # [Match]
        match_section = unit_parser["Match"]
        match_section["Driver"] = "veth"
        match_section["Name"] = f"ve-{self.name}"

        # [Network]
        network_section = unit_parser["Network"]
        network_section["DHCPServer"] = "yes"
        network_section["EmitLLDP"] = "customer-bridge"
        network_section["IPForward"] = "yes"
        network_section["LLDP"] = "yes"

        if profile_data["network"]["v4"]["nat"]:
            network_section["IPMasquerade"] = "yes"

        if profile_data["network"]["v6"]["addrPool"] != []:
            print("Warning: IPv6 SLAAC currently not supported for imperative containers!")

        # Check all possible network configurations for addresses
        for ips in [
            profile_data["network"]["v4"]["addrPool"],
            profile_data["network"]["v6"]["addrPool"],
            profile_data["network"]["v4"]["static"]["hostAddresses"],
            profile_data["network"]["v6"]["static"]["hostAddresses"],
        ]:
            for ip in ips:
                network_section["Address"] = ip

        with self.__network_unit_file.open("w+") as unit_fd:
            unit_parser.write(unit_fd, space_around_delimiters=False)

    def write_nspawn_unit_file(self) -> None:
        unit_parser = SystemdUnitParser()
        profile_data = self.profile_data

        # [Exec]
        exec_section = unit_parser["Exec"]
        exec_section["Boot"] = "false"
        exec_section["Parameters"] = str(self.__nix_path / "init")
        exec_section["PrivateUsers"] = "yes"
        exec_section["X-ActivationStrategy"] = self.activation_strategy
        exec_section["X-Imperative"] = "1"

        if profile_data.get("ephemeral"):
            exec_section["Ephemeral"] = "true"
        else:
            exec_section["LinkJournal"] = "guest"

        # [Files]
        files_section = unit_parser["Files"]
        files_section["BindReadOnly"] = "/nix/store"
        files_section["BindReadOnly"] = "/nix/var/nix/db"
        files_section["BindReadOnly"] = "/nix/var/nix/daemon-socket"
        files_section["PrivateUsersChown"] = "yes"

        # [Network]
        network_section = unit_parser["Network"]

        if network := profile_data.get("network"):
            network_section["Private"] = "true"
            network_section["VirtualEthernet"] = "true"

        if zone := profile_data.get("zone"):
            network_section["Zone"] = zone

        if network and not zone:
            self._write_network_unit_file()

        for forward_port in profile_data.get("forwardPorts", []):
            network_section["Port"] = forward_port

        with self.unit_file.open("w+") as unit_fd:
            unit_parser.write(unit_fd, space_around_delimiters=False)

    def create_state_directories(self) -> None:
        etc = self.__state_dir / "etc"
        etc.mkdir(parents=True, exist_ok=True)
        (etc / "os-release").touch(exist_ok=True)

    def get_runtime_property(self, key: str) -> str:
        rc, stdout = run_command(
            ["machinectl", "show", self.name, "--property", key, "--value"], capture_stdout=True
        )
        return stdout

    def run_command(self, args: list[str], capture_stdout: bool = False) -> tuple[int, str]:
        """Runs a command within the container"""
        leader_pid = self.get_runtime_property("Leader").strip()
        return run_command(
            ["nsenter", "-t", leader_pid, *NSENTER_ARGS, "--", *args], capture_stdout=capture_stdout
        )

    def start(self) -> None:
        run_command(["machinectl", "start", self.name])

    def reboot(self) -> None:
        run_command(["machinectl", "reboot", self.name])

    def poweroff(self) -> None:
        run_command(["machinectl", "poweroff", self.name])

    def reload(self) -> None:
        switcher = self.__nix_path / "bin" / "switch-to-configuration"
        self.run_command([str(switcher), "test"])

    def rollback(self) -> None:
        run_command(["nix-env", "-p", str(self.__nix_path), "--rollback"])

    def get_generations(self) -> list[NixGeneration]:
        rc, stdout = run_command(
            ["nix-env", "-p", str(self.__nix_path), "--list-generations"], capture_stdout=True
        )
        return [NixGeneration.from_list_output(gen) for gen in stdout.split("\n")]

    def activate_config(self, strategy: Optional[str] = None) -> None:
        if strategy is None:
            strategy = self.activation_strategy

        if strategy.lower().strip() == "restart":
            self.reboot()
        else:
            self.reload()

    def destroy(self) -> None:
        """Removes all files associated with the contanier."""
        self.unit_file.unlink(missing_ok=True)
        self.__network_unit_file.unlink(missing_ok=True)
        if self.__profile_dir.exists():
            rmtree(str(self.__profile_dir))
        if self.__state_dir.exists():
            rmtree(str(self.__state_dir))
