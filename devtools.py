#!/usr/bin/env nix-shell
#!nix-shell -i python3 shell.nix
import os
import shlex
import shutil
import sys
from argparse import ArgumentParser
from pathlib import Path
from subprocess import run
from typing import Any, Dict, List, Union

IS_WINDOWS = os.name == "nt"
CWD = Path(__file__).parent
VENV_DEV = CWD / ".venv"
VENV_SCRIPTS = VENV_DEV / "Scripts"
VENV_SCRIPTS = VENV_DEV / "Scripts" if IS_WINDOWS else VENV_DEV / "bin"
PATH = str(VENV_SCRIPTS) + os.pathsep + os.environ["PATH"]
DEFAULT_ENV = dict(os.environ)

with open(CWD / Path("nixos_nspawn", "version.txt"), "r") as version_file:
    VERSION = version_file.readline().strip()

COMMANDS = {}


def register_command(name: str) -> Any:
    def decorate(func: Any) -> Any:
        COMMANDS[name] = func
        return func

    return decorate


def run_cmd(cmd: str, env: Dict = DEFAULT_ENV) -> None:
    print(cmd)
    args: Union[str, list] = cmd
    if IS_WINDOWS:
        args = shlex.split(cmd)
    result = run(args, shell=True, env=env)
    if result.returncode != 0:
        exit(result.returncode)


@register_command("cleancache")
def cleancache() -> None:
    for deldir in (CWD / "nixos_nspawn").rglob("__pycache__"):
        shutil.rmtree(deldir, ignore_errors=True)
    for delfile in (CWD / "nixos_nspawn").rglob("*.pyc"):
        delfile.unlink(missing_ok=True)
    for delfile in CWD.glob("*.egg-info"):
        delfile.unlink(missing_ok=True)
    if (CWD / "build").exists():
        shutil.rmtree((CWD / "build"), ignore_errors=True)


@register_command("venv_dev")
def venv_dev() -> None:
    if not VENV_DEV.exists():
        run_cmd(f"python -m venv '{VENV_DEV}'")
    run_cmd(f"'{VENV_SCRIPTS / 'python'}' -m pip install -U pip")
    run_cmd(f"'{VENV_SCRIPTS / 'pip'}' install -U pip-compile-multi pip-tools")


@register_command("requirements")
def requirements() -> None:
    venv_dev()
    # pip-compile-multi handles virtualenvs very badly
    path = str(VENV_SCRIPTS) + os.pathsep + os.environ["PATH"]
    pythonpath = str(VENV_DEV / "Lib" / "site-packages")
    run_cmd(
        f"'{VENV_SCRIPTS / 'pip-compile-multi'}' --allow-unsafe",
        env={**os.environ, "PATH": path, "PYTHONPATH": pythonpath},
    )


@register_command("install_reqs")
def install_reqs() -> None:
    venv_dev()
    run_cmd(f"'{VENV_SCRIPTS / 'pip-sync'}' requirements/dev.txt")


@register_command("wheel")
def wheel() -> None:
    venv_dev()
    cleancache()
    run_cmd(f"'{VENV_SCRIPTS / 'python'}' setup.py bdist_wheel")


@register_command("pex")
def pex() -> None:
    venv_dev()
    cleancache()
    run_cmd(f"'{VENV_SCRIPTS / 'pip3'}' install 'pex>=2.1,<3'")
    run_cmd(
        f"'{VENV_SCRIPTS / 'pex'}'"
        " --python-shebang '/usr/bin/env python3'"
        f" --python '{VENV_SCRIPTS / 'python'}'"
        " -r requirements/prod.txt"
        f" -o dist/nixos_nspawn-{VERSION}.pex"
        " -m nixos_nspawn ."
    )


@register_command("test")
def test() -> None:
    install_reqs()
    run_cmd(f"'{VENV_SCRIPTS / 'isort'}' nixos_nspawn")
    run_cmd(f"'{VENV_SCRIPTS / 'black'}' nixos_nspawn")
    run_cmd(f"'{VENV_SCRIPTS / 'flake8'}' nixos_nspawn")
    # run_cmd(f"'{VENV_SCRIPTS / 'python'}' -m unittest discover -p 'test_*.py'")


@register_command("clean")
def clean() -> None:
    cleancache()
    for delfile in (CWD / "requirements").glob("*.txt"):
        delfile.unlink()
    if (CWD / "dist").exists():
        shutil.rmtree((CWD / "dist"), ignore_errors=True)
    if VENV_DEV.exists():
        shutil.rmtree(VENV_DEV, ignore_errors=True)


@register_command("init")
def init() -> None:
    requirements()
    install_reqs()
    print("Repo initialization completed")


@register_command("launch")
def launch() -> None:
    run_cmd(
        f"'{VENV_SCRIPTS / 'python'}' -m nixos_nspawn "
        + " ".join(f"'{arg}'" for arg in sys.argv[2:])
    )


def main(args: List[str]) -> None:
    parser = ArgumentParser("devtools")
    parser.add_argument("command", choices=list(COMMANDS.keys()))
    COMMANDS[parser.parse_args(args).command]()


if __name__ == "__main__":
    main(sys.argv[1:2])
