from abc import abstractmethod
from typing import Protocol


class Printable(Protocol):
    """Any dataclass that can be shown on the CLI should implement this"""

    @abstractmethod
    def render(self) -> str:
        """Generate a [rich] text human readable representation of this object"""

    @abstractmethod
    def to_dict(self) -> dict:
        """Transforms the object to a dictionary"""
