from argparse import ArgumentParser
from pathlib import Path
from typing import Optional

from ..constants import RC_CONTAINER_MISSING
from ._command import BaseCommand, Command


class UpdateCommand(BaseCommand, Command):
    """Update a container present on the system"""

    name = "update"
    needs_name = True
    supports_json = True

    @classmethod
    def register_arguments(cls, parser: ArgumentParser) -> None:
        super().register_arguments(parser)
        parser.add_argument("config", help="Container configuration file", type=Path)
        parser.add_argument(
            "--strategy",
            help=(
                "Activation strategy to use to apply the update to the container."
                " Leave blank to use strategy configured in the container's configuration."
            ),
            choices=["reload", "restart"],
        )

    def run(self) -> int:
        name: str = self.parsed_args.name
        config: Path = self.parsed_args.config
        strategy: Optional[str] = self.parsed_args.strategy

        container = self.manager.get(name)

        if not container:
            self._rprint(f"[red]Container [bold]{name}[/bold] does not exist![/red]")
            # Distinguishable return code from other exceptions
            return RC_CONTAINER_MISSING

        self.manager.update(container=container, config=config, activation_strategy=strategy)

        self._jprint(container.to_dict())
        self._rprint(
            f"Container [bold]{name}[/bold] updated [green]successfully[/green]. Details:\n"
            + container.render()
        )

        return 0
