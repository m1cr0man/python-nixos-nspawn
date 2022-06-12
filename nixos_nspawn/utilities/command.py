from logging import getLogger
from subprocess import PIPE, Popen


class CommandError(BaseException):
    def __init__(self, command: list[str], *args: object) -> None:
        self.command = command
        super().__init__(*args)


def run_command(args: list[str], capture_stdout: bool = False) -> tuple[int, str]:
    """Run a command and return the exit code"""
    logger = getLogger("nixos_nspawn.command")
    logger.debug("Running command '%s'", " ".join(args))

    process = Popen(args, stdout=PIPE if capture_stdout else None)
    exit_code = process.wait()

    stdout = ""
    if process.stdout:
        stdout = process.stdout.read().strip().decode("utf-8")

    logger.debug("Command finished with code %d and stdout '%s'", exit_code, stdout)

    if exit_code > 0:
        raise Exception(f"Command '{' '.join(args)}' failed with exit code {exit_code}! {stdout}")

    return (exit_code, stdout)
