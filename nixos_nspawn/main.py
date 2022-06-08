import sys
from argparse import ArgumentParser
from pathlib import Path

from nixos_nspawn import commands, metadata

COMMANDS = [
    commands.ListCommand,
]


def main(args: list[str]) -> int:
    parser = ArgumentParser(
        prog=args[0], description=f"NixOS imperative container manager v{metadata.version}"
    )

    parser.add_argument(
        "--unit-file-dir",
        help="Directory where Systemd nspawn container unit files are stored.",
        type=Path,
        default=Path("/etc/systemd/nspawn"),
    )
    subparsers = parser.add_subparsers(dest="command", help="Command to execute", required=True)

    # Register all the commands
    for command in COMMANDS:
        cmd_parser = subparsers.add_parser(command.name)
        cmd_parser.set_defaults(handler=command)
        command.register_arguments(cmd_parser)

    parsed_args = parser.parse_args(args[1:])

    # Run the command that was selected
    handler: type[commands.Command] = parsed_args.handler

    return handler(parsed_args, parsed_args.unit_file_dir).run()


def main_with_args() -> int:
    return main(sys.argv)


if __name__ == "__main__":
    sys.exit(main_with_args())
