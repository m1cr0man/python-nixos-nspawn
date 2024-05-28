from argparse import ArgumentParser
from logging import getLogger

from ..models import Container
from ._command import BaseCommand, Command


class AutostartCommand(BaseCommand, Command):
    """Start all imperative containers on the system which are configured to start at boot time"""

    name = "autostart"
    supports_json = True
    needs_name = False

    @classmethod
    def register_arguments(cls, parser: ArgumentParser) -> None:
        super().register_arguments(parser)
        parser.add_argument(
            "-n",
            "--dry-run",
            help="Show which containers would be started",
            action="store_true",
            default=False,
        )

    def run(self) -> int:
        dry_run: bool = self.parsed_args.dry_run
        logger = getLogger("nixos_nspawn")
        containers = self.manager.list()
        results: list[Container] = []

        for container in containers:
            if not container.is_managed:
                logger.debug(f"Skipping unmanaged container {container.unit_file}")
            elif container.state != "powered off":
                logger.debug(f"Skipping container {container.unit_file} in state {container.state}")
            elif container.is_imperative and container.autostart:
                results.append(container)
                dry_run or container.start()
            else:
                logger.debug(
                    f"Skipping {container.is_imperative and 'imperative' or 'declarative'} container {container.name}"
                )

        action = "Would start" if dry_run else "Started"
        self._rprint(f"{action} {len(results)} of {len(containers)} containers:")

        for container in results:
            self._rprint(container.render())

        self._jprint([c.to_dict() for c in results])

        return 0
