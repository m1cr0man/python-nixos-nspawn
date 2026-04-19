# Upstream Tooling

`nixos-nspawn` does not aim to be a one-stop shop for all container operations. Instead, we
leave it to the user to use the appropriate systemd-provided tooling where appropriate, of
which there are a few notable commands and flags you can use.

## The --machine/-M flag

Many systemd commands like `systemctl` and `journalctl` support a `--machine` (`-M` for short)
flag to target a specific nspawn container on the host. This can save you the hassle of
launching a shell just to perform basic system operations:

```sh
# List all services in a container
systemctl -M mycontainer --type=service

# Get the recent logs for a particular service
journalctl -M mycontainer -eu nginx.service

# Run a command inside the container in a new exec unit
systemd-run -M mycontainer -u testunit --collect --service-type=exec $(which ping) -c1 localhost

```

## machinectl operations

`machinectl` is one such tool part of the nspawn ecosystem which facilitates many different
container administrative operations.

### machinectl crash course

```sh
# List running containers plus up to 3 IP addresses
machinectl --max-addresses=3

# Invoke a shell within the container
machinectl shell mycontainer

# Alternative to the earlier systemd-run example.
# Note this does not propagate return codes from the invoked process.
machinectl shell mycontainer $(which ping) -c1 localhost

# Restart a container
machinectl reboot mycontainer

# (Advanced) Show the .nspawn unit definition for the container
machinectl cat mycontainer
```
