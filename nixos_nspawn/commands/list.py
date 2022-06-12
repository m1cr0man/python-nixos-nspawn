from ._command import BaseCommand, Command


class ListCommand(BaseCommand, Command):
    """List containers on the system"""

    name = "list"
    supports_json = True

    def run(self) -> int:
        containers = self.manager.list()
        results: list[dict] = []

        self._rprint(f"Showing [blue]{len(containers)}[/blue] containers:")

        for container in containers:
            results.append(container.to_dict())
            self._rprint(container.render())

        self._jprint(results)

        return 0
