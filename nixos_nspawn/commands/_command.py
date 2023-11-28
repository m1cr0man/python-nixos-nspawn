from abc import abstractmethod
from argparse import ArgumentParser, Namespace
from json import dumps
from typing import Any, ClassVar, Protocol

import rich

from ..manager import NixosNspawnManager


class Command(Protocol):
    """Protocol definition for a Command"""

    """Command line argument name for this Command"""
    name: ClassVar[str]

    parsed_args: Namespace
    manager: NixosNspawnManager

    def __init__(self, parsed_args: Namespace, manager: NixosNspawnManager) -> None:
        ...

    @classmethod
    @abstractmethod
    def register_arguments(cls, parser: ArgumentParser) -> None:
        """Adds any optional or required arguments for this Command to the given parser"""
        ...

    @abstractmethod
    def run(self) -> int:
        """The business logic of this Command"""
        ...


class BaseCommand(object):
    """Utilities shared by all Commands"""

    """Whether to provide a --json output toggle for this Command"""
    supports_json: ClassVar[bool] = False

    """Whether to require a name positional argument for this Command"""
    needs_name: ClassVar[bool] = False

    def __init__(self, parsed_args: Namespace, manager: NixosNspawnManager) -> None:
        # The initializer for the commands must reside outside of
        super(BaseCommand, self).__init__(parsed_args, manager)
        self.parsed_args = parsed_args
        self.manager = manager

    @classmethod
    def register_arguments(cls, parser: ArgumentParser) -> None:
        """Adds any optional or required arguments for this Command to the given parser"""
        if cls.supports_json:
            parser.add_argument(
                "--json", help="Output in JSON format", action="store_true", default=False
            )
        if cls.needs_name:
            parser.add_argument("name", help="Container name")

    @property
    def _json(self) -> bool:
        """True if JSON support is enabled for this Command and it is toggled ON"""
        return self.supports_json and self.parsed_args.json

    def _rprint(self, *vals: Any) -> None:  # noqa: ANN401
        """Prints the given values with rich if the JSON flag is toggled OFF"""
        if not self._json:
            rich.print(*vals)

    def _jprint(self, val: Any) -> None:  # noqa: ANN401
        """Prints the given value as JSON if the JSON flag is toggled ON"""
        if self._json:
            print(dumps(val))
