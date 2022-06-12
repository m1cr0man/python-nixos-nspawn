from argparse import ArgumentParser
from pathlib import Path

from ._command import BaseCommand, Command


class CreateCommand(BaseCommand, Command):
    """Create containers on the system"""

    name = "create"
    supports_json = True

    @classmethod
    def register_arguments(cls, parser: ArgumentParser) -> None:
        parser.add_argument("name", help="Container name", required=True)
        parser.add_argument("config", help="Container configuration file", type=Path, required=True)
        return super().register_arguments(parser)

    def run(self) -> int:
        name: str = self.parsed_args.name
        config: Path = self.parsed_args.config

        container = self.manager.create(name=name, config=config)

        self._jprint(container.to_dict())
        self._rprint("Created container. Details:" + container.render())

        return 0
