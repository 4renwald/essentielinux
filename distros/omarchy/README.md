# Omarchy

Omarchy ships the whole desktop — Hyprland, Quickshell, fish, themes — so this
distro's setup stays deliberately small. It installs packages and the managed
fish configuration, and leaves Omarchy's own configuration and services alone.

## Steps

| Step | Name | What it does |
| --- | --- | --- |
| 10 | Packages | Applications from the official repositories and the AUR through yay |
| 20 | Dotfiles | The Arch shell toolchain (minus Caelestia), the managed fish configuration, and agent skills for opencode, Claude Code, and Codex CLI |

Run from a fresh Omarchy install:

```bash
./install.sh
```

The installer recognizes Omarchy through its own markers (the `omarchy` CLI,
the `[omarchy]` repository in `/etc/pacman.conf`, or `/etc/omarchy-release`)
even though `/etc/os-release` still reports `ID=arch`. Fish and agent files
that the deployment replaces are backed up under
`~/.config-backup/omarchy-<timestamp>`.
