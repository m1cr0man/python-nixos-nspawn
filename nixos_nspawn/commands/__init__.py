from ._command import Command
from .create import CreateCommand
from .autostart import AutostartCommand
from .list import ListCommand
from .list_generations import ListGenerationsCommand
from .remove import RemoveCommand
from .rollback import RollbackCommand
from .update import UpdateCommand


COMMANDS = [
    AutostartCommand,
    CreateCommand,
    ListCommand,
    ListGenerationsCommand,
    RemoveCommand,
    RollbackCommand,
    UpdateCommand,
]

__all__ = [
    "Command",
    "COMMANDS",
    "AutostartCommand",
    "CreateCommand",
    "ListCommand",
    "ListGenerationsCommand",
    "RemoveCommand",
    "RollbackCommand",
    "UpdateCommand",
]
