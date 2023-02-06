from pathlib import Path
from typing import Optional

import rich


def check_config_or_flake(config: Optional[Path], flake: Optional[str]) -> int:
    if config and flake:
        rich.print(
            "[red]Options [bold]--config[/bold] and [bold]--flake[/bold] are"
            " mutually exclusive, please specify only one.[/red]"
        )
        return 1

    if not (config or flake):
        rich.print(
            "[red]One of [bold]--config[/bold] or [bold]--flake[/bold] must be specified.[/red]"
        )
        return 1

    return 0
