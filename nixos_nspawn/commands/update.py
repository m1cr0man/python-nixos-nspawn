from argparse import ArgumentParser
from pathlib import Path
from typing import Optional

from ..constants import RC_CONTAINER_MISSING
from ..metadata import default_system
from ._command import BaseCommand, Command
from ._shared import check_config_or_flake


class UpdateCommand(BaseCommand, Command):
    """Update a container present on the system"""

    name = "update"
    needs_name = True
    supports_json = True

    @classmethod
    def register_arguments(cls, parser: ArgumentParser) -> None:
        super().register_arguments(parser)
        parser.add_argument("--config", help="Container configuration file", type=Path)
        parser.add_argument("--flake", help="Container configuration flake path", type=str)
        parser.add_argument(
            "--strategy",
            help=(
                "Activation strategy to use to apply the update to the container."
                " Leave blank to use strategy configured in the container's configuration."
            ),
            choices=["reload", "restart"],
        )
        parser.add_argument(
            "--system",
            help=f"The host platform name. The default ({default_system})"
            " is selected at compile time.",
            type=str,
            default=default_system,
        )

    def run(self) -> int:
        name: str = self.parsed_args.name
        strategy: Optional[str] = self.parsed_args.strategy
        config: Optional[Path] = self.parsed_args.config
        flake: Optional[str] = self.parsed_args.flake
        system: str = self.parsed_args.system

        if rc := check_config_or_flake(config, flake):
            return rc

        container = self.manager.get(name)

        if not container:
            self._rprint(f"[red]Container [bold]{name}[/bold] does not exist![/red]")
            # Distinguishable return code from other exceptions
            return RC_CONTAINER_MISSING

        self.manager.update(
            container=container,
            config=config,
            flake=flake,
            system=system,
            activation_strategy=strategy,
        )

        self._jprint(container.to_dict())
        self._rprint(
            f"Container [bold]{name}[/bold] updated [green]successfully[/green]. Details:\n"
            + container.render()
        )

        return 0
