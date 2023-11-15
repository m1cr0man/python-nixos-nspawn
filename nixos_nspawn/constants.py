from pathlib import Path

DEFAULT_NSPAWN_DIR = Path("/etc/systemd/nspawn")

NIX_PROFILE_DIR = Path("/nix/var/nix/profiles/per-nspawn")

MACHINE_STATE_DIR = Path("/var/lib/machines")

NSENTER_ARGS = ["-m", "-u", "-U", "-i", "-n", "-p"]

RC_CONTAINER_MISSING = 2

DEFAULT_EVAL_SCRIPT = Path(__file__).parent / "nix" / "eval-config.nix"

FLAKE_KEY = "nixosContainers"
