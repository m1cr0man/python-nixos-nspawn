# NixOS NSpawn Manager

Rewrite of the Nix RFC 108 POC imperative container manager.

# Installation

nixos_nspawn can be installed as a flake from this repository.
A super quick way to get started is:

```bash
nix run github:m1cr0man/python-nixos-nspawn -- --help
```

# Usage + Commands

## Creating a container

- Create a Nix configuration for the container, following the below example:

```nix

```

# Development environment setup

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

## Updating dependencies

*Note*: Due to [a bug](https://github.com/nix-community/poetry2nix/issues/701#issuecomment-1229790215),
ensure Poetry is >= 1.1.14.

```bash
# Update poetry lockfile
nix run nixpkgs#poetry -- lock
# Update flake lockfile
nix flake update
```
