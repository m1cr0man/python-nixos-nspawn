from dataclasses import dataclass
from pathlib import Path

from ._printable import Printable


@dataclass
class Container(Printable):
    unit_file: Path

    @property
    def name(self) -> str:
        return self.unit_file.name[: -len(".nspawn")]

    @classmethod
    def from_unit_file(cls, unit_file: Path) -> "Container":
        return cls(unit_file)

    def render(self) -> str:
        return "\n".join(
            (
                f"[bold]{self.name}[/bold]",
                f"  Unit File: {self.unit_file}",
            )
        )
