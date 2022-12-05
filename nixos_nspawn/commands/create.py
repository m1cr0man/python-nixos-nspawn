from argparse import ArgumentParser
from pathlib import Path
from typing import Optional

from ..constants import RC_CONTAINER_MISSING
from ..metadata import system
from ._command import BaseCommand, Command
from ._shared import check_config_or_flake


class CreateCommand(BaseCommand, Command):
    """Create a container on the system"""

    name = "create"
    needs_name = True
    supports_json = True

    @classmethod
    def register_arguments(cls, parser: ArgumentParser) -> None:
        super().register_arguments(parser)
        parser.add_argument("--config", help="Container configuration file", type=Path)
        parser.add_argument("--flake", help="Container configuration flake path", type=str)
        parser.add_argument(
            "--system",
            help=f"The host platform name. The default ({system}) is selected at compile time.",
            type=str,
            default=system,
        )

    def run(self) -> int:
        name: str = self.parsed_args.name
        config: Optional[Path] = self.parsed_args.config
        flake: Optional[str] = self.parsed_args.flake
        system: str = self.parsed_args.system

        if rc := check_config_or_flake(config, flake):
            return rc

        try:
            container = self.manager.create(name=name, config=config, flake=flake, system=system)
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
