from argparse import ArgumentParser
from logging import getLogger

from ..models import Container
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
        results: list[Container] = []
        logger = getLogger("nixos_nspawn")

        for container in containers:
            if not container.is_managed:
                logger.debug(f"Skipping unmanaged container {container.unit_file}")
            elif (
                not container_type
                or (container_type == "imperative" and container.is_imperative)
                or (container_type == "declarative" and not container.is_imperative)
            ):
                results.append(container)
            else:
                logger.debug(
                    f"Skipping {container.is_imperative and 'imperative' or 'declarative'} container {container.name}"
                )

        self._rprint(f"Showing {len(results)} of {len(containers)} containers:")

        for container in results:
            self._rprint(container.render())

        self._jprint([c.to_dict() for c in results])

        return 0
