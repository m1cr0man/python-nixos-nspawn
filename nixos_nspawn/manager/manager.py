from logging import getLogger
from os import sync
from pathlib import Path
from typing import Optional

from ..constants import DEFAULT_NSPAWN_DIR
from ..metadata import default_system
from ..models import Container


class NixosNspawnManagerError(BaseException):
    ...


class NixosNspawnManager(object):
    def __init__(self, unit_file_dir: Path = DEFAULT_NSPAWN_DIR, show_trace: bool = False) -> None:
        self.unit_file_dir = unit_file_dir
        self.show_trace = show_trace

        self.__containers: list[Container] = []
        self.__logger = getLogger("nixos_nspawn.manager")
        self.load()

    def load(self) -> None:
        """Load existing containers from the filesystem. Required to initialise this class"""
        self.__containers = [
            Container.from_unit_file(unit_file) for unit_file in self.unit_file_dir.glob("*.nspawn")
        ]
        self.__logger.debug(
            "Loaded %s containers from %s", len(self.__containers), self.unit_file_dir
        )

    def get(self, name: str) -> Optional[Container]:
        for container in self.__containers:
            if container.name == name:
                return container

    def list(self) -> list[Container]:
        # Avoid a reference pass of our internal containers list
        return list(self.__containers)

    def _check_network_zone(self, container: Container) -> None:
        # Check that the virtual network zone exists
        if (zone := container.profile_data.get("zone")) and not (
            zone_path := Path(f"/sys/class/net/vz-{zone}")
        ).exists():
            self.__logger.debug("Could not find %s", zone_path)
            raise NixosNspawnManagerError(f"Virtual zone '{zone}' does not exist!")

    def build(
        self,
        container: Container,
        config: Optional[Path] = None,
        flake: Optional[str] = None,
        system: str = default_system,
        update: bool = False,
    ) -> Path:
        if config:
            return container.build_nixos_config(config, update=update, show_trace=self.show_trace)
        if flake:
            return container.build_flake_config(
                flake, system=system, update=update, show_trace=self.show_trace
            )
        raise AssertionError("Either a config or flake must be specified when calling build()")

    def create(
        self,
        name: str,
        config: Optional[Path] = None,
        flake: Optional[str] = None,
        system: str = default_system,
    ) -> Container:
        container = Container(unit_file=self.unit_file_dir / f"{name}.nspawn")

        if container in self.__containers:
            raise NixosNspawnManagerError(f"Container [bold]{name}[/bold] already exists!")

        self.__logger.debug(
            "Creating container [bold]%s[/bold] with config '%s'", name, config or flake
        )

        try:
            self.build(container, config, flake, system)
            self._check_network_zone(container)
            container.write_config_files()
            container.create_state_directories()
            sync()
            container.start()

        except Exception as err:
            # If the build fails, ensure nothing is left behind.
            container.destroy()
            raise err

        self.__containers.append(container)

        return container

    def update(
        self,
        container: Container,
        config: Optional[Path] = None,
        flake: Optional[str] = None,
        system: str = default_system,
        activation_strategy: Optional[str] = None,
    ) -> None:
        self.__logger.debug(
            "Updating container [bold]%s[/bold] with config '%s'."
            " Activation strategy override: %s",
            container.name,
            config or flake,
            activation_strategy,
        )

        self.build(container, config, flake, system, update=True)
        self._check_network_zone(container)
        container.write_config_files()
        container.create_state_directories()
        sync()

        container.activate_config(activation_strategy)

    def rollback(self, container: Container, activation_strategy: Optional[str] = None) -> None:
        self.__logger.debug(
            "Rolling back container [bold]%s[/bold]. Activation strategy override: %s",
            container.name,
            activation_strategy,
        )

        container.rollback()
        container.write_config_files()
        container.create_state_directories()
        sync()

        container.activate_config(activation_strategy)

    def remove(self, container: Container) -> None:
        self.__logger.debug(
            "Removing container [bold]%s[/bold]",
            container.name,
        )

        if container.get_runtime_property("State", ignore_error=True):
            container.poweroff()
        container.destroy()

        self.__containers.remove(container)
