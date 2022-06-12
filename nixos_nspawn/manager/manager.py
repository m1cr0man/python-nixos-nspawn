from os import sync
from pathlib import Path

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

    def list(self) -> list[Container]:
        # Avoid a reference pass of our internal containers list
        return list(self.__containers)

    def create(self, name: str, config: Path) -> Container:
        container = Container(unit_file=self.unit_file_dir / f"{name}.nspawn")

        if container.unit_file in self.__containers:
            raise Exception(f"Container {name} already exists!")

        container.build_nixos_config(config)

        # Check that the virtual network zone exists
        if (zone := container.profile_data.get("zone")) and not Path(
            f"/sys/class/net/vz-{zone}"
        ).exists():
            raise Exception(f"Virtual zone {zone} does not exist!")

        container.write_nspawn_unit_file()
        container.create_state_directories()
        sync()

        # TODO:
        # self.__activate
        # run machinectl start
        # Use logger where possible/necessary

        self.__containers.append(container)

        return container
