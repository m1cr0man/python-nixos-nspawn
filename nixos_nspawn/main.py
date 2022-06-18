import logging
import sys
from argparse import ArgumentParser
from pathlib import Path

from rich.logging import RichHandler
from rich.traceback import install as install_rich

from nixos_nspawn import commands, constants, manager, metadata, models, utilities

COMMANDS = [
    commands.CreateCommand,
    commands.ListCommand,
    commands.ListGenerationsCommand,
    commands.RemoveCommand,
    commands.RollbackCommand,
    commands.UpdateCommand,
]


def main(args: list[str]) -> int:
    parser = ArgumentParser(description=f"NixOS imperative container manager v{metadata.version}")

    parser.add_argument(
        "--unit-file-dir",
        help="Directory where Systemd nspawn container unit files are stored",
        type=Path,
        default=constants.DEFAULT_NSPAWN_DIR,
    )
    parser.add_argument(
        "-v",
        "--verbose",
        help="Show build traces and other command activity",
        action="store_true",
        default=False,
    )
    subparsers = parser.add_subparsers(dest="command", help="Command to execute", required=True)

    # Register all the commands
    for command in COMMANDS:
        cmd_parser = subparsers.add_parser(
            command.name, help=command.__doc__, description=command.__doc__
        )
        cmd_parser.set_defaults(handler=command)
        command.register_arguments(cmd_parser)

    parsed_args = parser.parse_args(args[1:])

    # Configure the logger
    logging.basicConfig(
        level=logging.DEBUG if parsed_args.verbose else logging.INFO,
        format="[dim]%(name)s:[/dim] %(message)s",
        datefmt="[%X]",
        handlers=[RichHandler(show_time=False, show_level=False, markup=True, show_path=False)],
    )
    logger = logging.getLogger("nixos_nspawn")

    # Use rich for trace handling
    install_rich(max_frames=20 if parsed_args.verbose else 3)

    # Prepare the manager
    mgr = manager.NixosNspawnManager(parsed_args.unit_file_dir, show_trace=parsed_args.verbose)

    # Run the command that was selected
    handler: type[commands.Command] = parsed_args.handler

    try:
        return handler(parsed_args, mgr).run()
    except (models.ContainerError, manager.NixosNspawnManagerError) as app_err:
        logger.fatal("[red]%s[/red]", app_err, exc_info=parsed_args.verbose)
        # Distinguishable return code from other exceptions
        return 10
    except utilities.CommandError as cmd_err:
        logger.fatal(
            "[red]Command '%s' failed with exit code %d\n%s[/red]",
            " ".join(cmd_err.command),
            cmd_err.exit_code,
            cmd_err,
            exc_info=parsed_args.verbose,
        )
        return 11
    except PermissionError as perms_err:
        logger.fatal(
            "[red]Encountered a '%s' error whilst accessing '%s'[/red]",
            perms_err.strerror,
            perms_err.filename,
            exc_info=parsed_args.verbose,
        )
        return 1


def main_with_args() -> int:
    return main(sys.argv)


if __name__ == "__main__":
    sys.exit(main_with_args())
