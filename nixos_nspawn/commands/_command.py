from abc import ABC, abstractmethod
from argparse import ArgumentParser, Namespace
from pathlib import Path


class Command(ABC):
    """Basic command"""

    def __init__(self, parsed_args: Namespace, unit_file_dir: Path) -> None:
        super(Command, self).__init__()
        self.parsed_args = parsed_args
        self.unit_file_dir = unit_file_dir

    @property
    @classmethod
    @abstractmethod
    def name(cls) -> str:
        raise NotImplementedError(
            f"{cls.__name__} does not implement 'name' property",
        )

    @classmethod
    @abstractmethod
    def register_arguments(cls, parser: ArgumentParser) -> None:
        raise NotImplementedError(
            f"{cls.__name__} does not implement 'register_arguments' method",
        )

    @abstractmethod
    def run(
        self,
    ) -> int:
        raise NotImplementedError(
            f"{self.__class__.__name__} does not implement 'run' method",
        )
