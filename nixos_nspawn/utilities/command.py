from logging import getLogger
from subprocess import PIPE, Popen
from typing import IO, Any


class CommandError(Exception):
    def __init__(self, command: list[str], exit_code: int, *args: object) -> None:
        self.command = command
        self.exit_code = exit_code
        super().__init__(*args)


def run_command(
    args: list[str],
    capture_stdout: bool = False,
    capture_stderr: bool = False,
    stdin: IO[Any] | None = None,
) -> tuple[int, str]:
    """Run a command and return the exit code"""
    logger = getLogger("nixos_nspawn.command")
    logger.debug("Running command '%s'", " ".join(args))

    with Popen(
        args,
        stdin=stdin,
        stdout=PIPE if capture_stdout else None,
        stderr=PIPE if capture_stderr else None,
    ) as process:
        exit_code = process.wait()

        stdout = ""
        if process.stdout:
            stdout = process.stdout.read().strip().decode("utf-8")

    logger.debug("Command finished with code %d and stdout '%s'", exit_code, stdout)

    if exit_code > 0:
        raise CommandError(args, exit_code, stdout)

    return (exit_code, stdout)
