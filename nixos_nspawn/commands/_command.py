from abc import ABC, abstractmethod, abstractproperty
from argparse import ArgumentParser


class Command(ABC):
    """Basic command"""

    @abstractmethod
    @classmethod
    def register_arguments(cls, parser: ArgumentParser) -> None:
        return
