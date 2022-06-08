from pathlib import Path


class Container(object):
    def __init__(self, unit_file: Path) -> None:
        self.unit_file = unit_file

        self.name = self.unit_file.name[: -len(".nspawn")]

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
