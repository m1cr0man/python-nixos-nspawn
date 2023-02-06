from dataclasses import asdict, dataclass

from ._printable import Printable


@dataclass
class NixGeneration(Printable):
    generation_id: int
    date: str
    label: str
    current: bool

    def render(self) -> str:
        output = "{:<3d}\t{}\t{}".format(self.generation_id, self.date, self.label)
        if self.current:
            return f"[green]{output}[/green]"

        return output

    def to_dict(self) -> dict:
        return asdict(self)

    @classmethod
    def from_list_output(cls, line: str) -> "NixGeneration":
        data = line.split()
        return cls(
            generation_id=int(data[0].strip()),
            date=data[1].strip(),
            label=data[2].strip(),
            current=data[2].strip() == "(current)",
        )
