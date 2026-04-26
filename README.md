# NixOS NSpawn Container Management

[Documentation Home](https://m1cr0man.github.io/python-nixos-nspawn/)

This repo provides tools and NixOS modules to support [Nix RFC 108](https://github.com/NixOS/rfcs/blob/master/rfcs/0108-nixos-containers.md)
declarative and imperative container management.

- `nixos-nspawn` tool for imperative container management compatible with non-NixOS systems.
- `nixos.containers` module for declarative container management.
- Unified implementation across both container types allowing for safe migration between them.
- `nixos_nspawn` is library-friendly for easy automation extension.

# One Command Demo

You can try imperative containers on any system with this one command subject to these requirements:

- Systemd version 256 or newer.
- Nix package manager is available with flakes enabled.
- Both /var/lib/machines and /etc/systemd/nspawn are writable.

```bash
$ sudo nix run github:m1cr0man/python-nixos-nspawn -- create --flake github:m1cr0man/python-nixos-nspawn#example example

nixos_nspawn.container.example: Building configuration from flake github:m1cr0man/python-nixos-nspawn#example
nixos_nspawn.container.example: Writing nspawn unit file
nixos_nspawn.container.example: Starting
Container example created successfully. Details:
Container example
  Unit File: /etc/systemd/nspawn/example.nspawn
  Imperative: True
  State: running
$ sudo machinectl enter
[root@example:~]#
```

Check out the full documentation: https://m1cr0man.github.io/python-nixos-nspawn/

# Development environment setup

This repository uses Nix. You can

```bash
# Get the dev tools in your environment
nix develop
# (VS Code) Open the workspace file
code python-nixos-nspawn.code-workspace
# Build and run the project
nix run
```

## Updating dependencies

```bash
# Update flake lockfile
nix flake update
```
