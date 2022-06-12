from argparse import ArgumentParser
from pathlib import Path

from ..constants import RC_CONTAINER_MISSING
from ._command import BaseCommand, Command


class CreateCommand(BaseCommand, Command):
    """Create a container on the system"""

    name = "create"
    needs_name = True
    supports_json = True

    @classmethod
    def register_arguments(cls, parser: ArgumentParser) -> None:
        super().register_arguments(parser)
        parser.add_argument("config", help="Container configuration file", type=Path)

    def run(self) -> int:
        name: str = self.parsed_args.name
        config: Path = self.parsed_args.config

        try:
            container = self.manager.create(name=name, config=config)
        except ValueError:
            self._rprint(f"[red]Container [bold]{name}[/bold] already exists![/red]")
            # Distinguishable return code from other exceptions
            return RC_CONTAINER_MISSING

        self._jprint(container.to_dict())
        self._rprint(
            f"Container [bold]{name}[/bold] created [green]successfully[/green]. Details:\n"
            + container.render()
        )

        return 0
