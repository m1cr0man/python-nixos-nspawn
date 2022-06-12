from argparse import ArgumentParser

from ._command import BaseCommand, Command


class ListCommand(BaseCommand, Command):
    """List containers on the system"""

    name = "list"
    supports_json = True

    @classmethod
    def register_arguments(cls, parser: ArgumentParser) -> None:
        parser.add_argument(
            "--type",
            help="Container type to filter by",
            choices=["imperative", "declarative"],
            default=None,
        )
        return super().register_arguments(parser)

    def run(self) -> int:
        container_type = self.parsed_args.type
        containers = self.manager.list()
        total = len(containers)
        results: list[dict] = []

        self._rprint(f"Showing {len(containers)} of {total} containers:")

        for container in containers:
            if (
                not container_type
                or (container_type == "imperative" and container.is_imperative)
                or (container_type == "declarative" and not container.is_imperative)
            ):
                results.append(container.to_dict())
                self._rprint(container.render())

        self._jprint(results)

        return 0
