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

- Run the [example container](./flake.nix#L90), which creates a system with
 python installed.

```bash
$ sudo nixos-nspawn create --flake github:m1cr0man/python-nixos-nspawn#example
$ sudo machinectl enter example
```

## Listing containers

- Use the `list` command to see all configured containers.

```bash
$ sudo nixos-nspawn list
Showing 1 of 1 containers:
Container example
  Unit File: /etc/systemd/nspawn/example.nspawn
  Imperative: True
  State: powered off
```

# Development environment setup

This repository uses Poetry. You can

```bash
# Get poetry in your environment
nix develop
# Create the virtualenv.
poetry install --no-root
# (VS Code) Open the workspace file
code python-nixos-nspawn.code-workspace
# Build and run the project
nix run
```

## Updating dependencies

*Note*: Due to [a bug](https://github.com/nix-community/poetry2nix/issues/701#issuecomment-1229790215),
ensure Poetry is >= 1.1.14.

```bash
# Update poetry lockfile
nix develop
poetry lock
# Update flake lockfile
nix flake update
```
