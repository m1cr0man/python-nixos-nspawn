from pathlib import Path

with (Path(__file__).parent / "version.txt").open("r") as version_file:
    version = version_file.readline().strip()

with (Path(__file__).parent / "system.txt").open("r") as system_file:
    default_system = system_file.readline().strip()
