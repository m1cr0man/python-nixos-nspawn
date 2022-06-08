from argparse import ArgumentParser

import rich

from ..models import Container
from ._command import Command


class ListCommand(Command):
    @classmethod
    @property
    def name(cls) -> str:
        return "list"

    @classmethod
    def register_arguments(cls, parser: ArgumentParser) -> None:
        # No extra arguments to register here
        return

    def run(self) -> None:
        unit_files = list(self.unit_file_dir.glob("*.nspawn"))
        rich.print(f"Showing {len(unit_files)} containers:")
        for unit_file in unit_files:
            container = Container.from_unit_file(unit_file)
            rich.print(container.render())
