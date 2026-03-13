from pathlib import Path
from typing import Optional

import rich


def check_config_source(config: Optional[Path], profile: Optional[Path], flake: Optional[str]) -> int:
    num_sources = sum((config and 1 or 0, profile and 1 or 0, flake and 1 or 0))
    if num_sources > 1:
        rich.print(
            "[red]Options [bold]--config[/bold], [bold]--profile[/bold] and [bold]--flake[/bold]"
            " are mutually exclusive, please specify only one.[/red]"
        )
        return 1

    if num_sources == 0:
        rich.print(
            "[red]One of [bold]--config[/bold], [bold]--profile[/bold] or [bold]--flake[/bold] must be specified.[/red]"
        )
        return 1

    return 0
