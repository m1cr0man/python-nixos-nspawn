from os import sync
from pathlib import Path
from typing import Optional

from ..models import Container


class NixosNspawnManager(object):
    def __init__(self, unit_file_dir: Path) -> None:
        self.unit_file_dir = unit_file_dir

        self.__containers: list[Container] = []
        self.load()

    def load(self) -> None:
        """Load existing containers from the filesystem. Required to initialise this class"""
        self.__containers = [
            Container.from_unit_file(unit_file) for unit_file in self.unit_file_dir.glob("*.nspawn")
        ]

    def get(self, name: str) -> Optional[Container]:
        for container in self.__containers:
            if container.name == name:
                return container

    def list(self) -> list[Container]:
        # Avoid a reference pass of our internal containers list
        return list(self.__containers)

    def _check_network_zone(self, container: Container) -> None:
        # Check that the virtual network zone exists
        if (zone := container.profile_data.get("zone")) and not Path(
            f"/sys/class/net/vz-{zone}"
        ).exists():
            raise Exception(f"Virtual zone {zone} does not exist!")

    def create(self, name: str, config: Path) -> Container:
        container = Container(unit_file=self.unit_file_dir / f"{name}.nspawn")

        if container in self.__containers:
            raise ValueError(f"Container {name} already exists!")

        container.build_nixos_config(config)
        self._check_network_zone(container)
        container.write_nspawn_unit_file()
        container.create_state_directories()
        sync()

        container.start()

        self.__containers.append(container)

        return container

    def update(
        self, container: Container, config: Path, activation_strategy: Optional[str] = None
    ) -> None:
        container.build_nixos_config(config)
        self._check_network_zone(container)
        container.write_nspawn_unit_file()
        sync()

        container.activate_config(activation_strategy)

    def rollback(self, container: Container, activation_strategy: Optional[str] = None) -> None:
        container.rollback()
        sync()

        container.activate_config(activation_strategy)

    def remove(self, container: Container) -> None:
        container.poweroff()
        container.destroy()

        self.__containers.remove(container)
