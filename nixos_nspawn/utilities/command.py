from os.path import basename
from subprocess import PIPE, Popen


def run_command(args: list[str], capture_stdout: bool = False) -> tuple[int, str]:
    """Run a command and return the exit code"""
    print("Running command", basename(args[0]))
    process = Popen(args, stdout=PIPE if capture_stdout else None)
    exit_code = process.wait()

    stdout = ""
    if process.stdout:
        stdout = process.stdout.read().strip().decode("utf-8")

    if exit_code > 0:
        raise Exception(f"Command '{' '.join(args)}' failed with exit code {exit_code}! {stdout}")

    return (exit_code, stdout)
