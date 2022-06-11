from abc import abstractmethod
from dataclasses import asdict
from typing import Protocol


class Printable(Protocol):
    """Any dataclass that can be shown on the CLI should implement this"""

    @abstractmethod
    def render(self) -> str:
        raise NotImplementedError(
            f"{type(self).__name__} does not implement 'name' property",
        )

    def to_dict(self) -> dict:
        return asdict(self)
