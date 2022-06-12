from ..constants import RC_CONTAINER_MISSING
from ._command import BaseCommand, Command


class ListGenerationsCommand(BaseCommand, Command):
    """List configuration generations of a container"""

    name = "list-generations"
    needs_name = True
    supports_json = True

    def run(self) -> int:
        name: str = self.parsed_args.name

        container = self.manager.get(name)

        if not container:
            self._rprint(f"[red]Container [bold]{name}[/bold] does not exist![/red]")
            # Distinguishable return code from other exceptions
            return RC_CONTAINER_MISSING

        generations = container.get_generations()

        self._jprint(generations)

        self._rprint(
            f"Showing {len(generations)} generations" f" for container [bold]{name}[/bold]:"
        )
        for generation in generations:
            self._rprint(generation.render())

        return 0
