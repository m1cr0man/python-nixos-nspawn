from ..models import Container
from ._command import BaseCommand, Command

# TODO other stuff


class ListCommand(BaseCommand, Command):
    """List containers on the system"""

    name = "list"
    supports_json = True

    def run(self) -> int:
        unit_files = list(self.unit_file_dir.glob("*.nspawn"))
        results: list[dict] = []

        self._rprint(f"Showing {len(unit_files)} containers:")

        for unit_file in unit_files:
            container = Container.from_unit_file(unit_file)
            results.append(container.to_dict())
            self._rprint(container.render())

        self._jprint(results)

        return 0
