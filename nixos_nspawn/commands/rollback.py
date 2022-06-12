from ..constants import RC_CONTAINER_MISSING
from ._command import BaseCommand, Command


class RollbackCommand(BaseCommand, Command):
    """Roll back a container on the system"""

    name = "rollback"
    needs_name = True
    supports_json = True

    def run(self) -> int:
        name: str = self.parsed_args.name

        container = self.manager.get(name)

        if not container:
            self._rprint(f"[red]Container [bold]{name}[/bold] does not exist![/red]")
            # Distinguishable return code from other exceptions
            return RC_CONTAINER_MISSING

        if len(container.get_generations()) < 2:
            self._rprint(
                f"[red]Container [bold]{name}[/bold] has no previous"
                " generations to roll back to![/red]"
            )
            return 3

        self._rprint(f"Rolling back container [bold]{name}[/bold]...")
        self.manager.rollback(container)
        self._rprint(f"Container [bold]{name}[/bold] rolled back [green]successfully[/green]")
        self._jprint(container)

        return 0
