# 🪩 dotfiles

> A fresh Linux install, dressed up and ready to dance.

This is my installer for Fedora, Arch, and Omarchy machines. It detects the distro, then sets up the packages, system files, and dotfiles for a native Hyprland desktop. Fedora uses Noctalia and Arch uses Caelestia; Omarchy already ships its own desktop, so there the installer only adds applications and the fish configuration. On Fedora and Arch, every detected Intel, AMD, and NVIDIA display GPU gets the matching driver stack, so hybrid machines are covered too.

## ✨ What you get

| Fedora 🎛️ | Arch 🎚️ | Omarchy 🐚 |
| --- | --- | --- |
| Hyprland + Noctalia | Hyprland + Caelestia | Preinstalled Hyprland + Quickshell |
| Ghostty themed by Noctalia | Ghostty themed by Caelestia | Omarchy's own desktop, untouched |
| Brave Origin, Equibop, VSCodium, Nextcloud, qBittorrent | Brave Origin, Equibop, VS Code, Nextcloud, qBittorrent | Brave Origin, Keeper, OpenCode Desktop, Obsidian, Proton Mail, Equibop, qBittorrent, Mullvad VPN, Nextcloud, Vaultwarden |
| PipeWire, gaming, printing, Snapper on btrfs | PipeWire, gaming, AUR tools, Snapper on btrfs | GitHub CLI, the fish + starship toolchain, the managed fish config, and agent skills for opencode, Claude Code, and Codex CLI |
| Python + uv, Go, WinBoat, Tailscale | Python + uv, Go, WinBoat, Tailscale | — |

## 🚀 Quick start

On a fresh machine (no cloning needed):

```bash
curl -fsSL https://raw.githubusercontent.com/4renwald/dotfiles/main/bootstrap.sh | bash
```

Or by hand:

```bash
git clone https://github.com/4renwald/dotfiles.git
cd dotfiles
./install.sh
reboot
```

## 🟢 Before you begin

Each distro needs a specific base install before running the installer:

- **Fedora:** [distros/fedora/README.md](distros/fedora/README.md)
- **Arch:** [distros/arch/README.md](distros/arch/README.md)
- **Omarchy:** [distros/omarchy/README.md](distros/omarchy/README.md) — a fresh install needs nothing extra

## 🎛️ Make it yours

```bash
./install.sh                # interactive: steps and package customization
./install.sh 20 30 55       # run specific steps only
./install.sh --list         # list the detected distro's steps
./install.sh --gpu amd 20   # override automatic GPU detection for this run
```

## ⚠️ Fresh installs only

Run as a regular user. The installer elevates once and that single authorization covers every privileged operation in the run. It is designed for one initial run on a fresh installation, not ongoing system reconciliation.
