from argparse import ArgumentParser

from ._command import BaseCommand, Command


class RemoveCommand(BaseCommand, Command):
    """Remove a container from the system"""

    name = "remove"
    needs_name = True

    @classmethod
    def register_arguments(cls, parser: ArgumentParser) -> None:
        parser.add_argument(
            "--delete-state",
            help="Delete the container's state directory",
            default=False,
            action='store_true',
        )
        return super().register_arguments(parser)

    def run(self) -> int:
        name: str = self.parsed_args.name

        container = self.manager.get(name)

        if not container:
            self._rprint(
                f"[yellow]Container [bold]{name}[/bold] does not exist; Nothing done.[/yellow]"
            )
            return 0

        self._rprint(f"Removing container [bold]{name}[/bold]...")
        self.manager.remove(container, delete_state=self.parsed_args.delete_state)
        self._rprint(f"Container [bold]{name}[/bold] removed [green]successfully[/green]")

        return 0
