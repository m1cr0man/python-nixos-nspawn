# NixOS NSpawn Manager

Rewrite of the Nix RFC 108 POC imperative container manager.

## Development environment setup

This repository uses Nix to manage environments.
Use the following commands to get started:

```bash
# Build the venv
nix build '.#nixos-nspawn-venv' --out-link .venv
# (VS Code) Open the workspace file
code python-nixos-nspawn.code-workspace
# Start a shell with dev dependencies available
nix develop
```
