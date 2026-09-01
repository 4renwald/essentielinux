# 🪩 essentielinux

> A fresh Linux install, dressed up and ready to dance.

This is my installer for Fedora and Arch machines. It detects the distro, then sets up the packages, system files, and dotfiles for a native Hyprland desktop. Fedora uses Noctalia and Arch uses Caelestia. Every detected Intel, AMD, and NVIDIA display GPU gets the matching driver stack, so hybrid machines are covered too.

## ✨ What you get

| Fedora 🎛️ | Arch 🎚️ |
| --- | --- |
| Hyprland + Noctalia | Hyprland + Caelestia |
| Ghostty themed by Noctalia | Ghostty themed by Caelestia |
| Brave Origin, Equibop, VSCodium, Nextcloud, qBittorrent | Brave Origin, Equibop, VS Code, Nextcloud, qBittorrent |
| PipeWire, gaming, printing, Snapper on btrfs | PipeWire, gaming, AUR tools, Snapper on btrfs |

## 🚀 Quick start

On a fresh machine (no cloning needed):

```bash
curl -fsSL https://raw.githubusercontent.com/4renwald/essentielinux/main/bootstrap.sh | bash
```

Or by hand:

```bash
git clone https://github.com/4renwald/essentielinux.git
cd essentielinux
./install.sh
reboot
```

## 🟢 Before you begin

Each distro needs a specific base install before running the installer:

- **Fedora:** [distros/fedora/README.md](distros/fedora/README.md)
- **Arch:** [distros/arch/README.md](distros/arch/README.md)

## 🎛️ Make it yours

```bash
./install.sh                # interactive: steps and package customization
./install.sh 20 30 55       # run specific steps only
./install.sh --list         # list the detected distro's steps
./install.sh --gpu amd 20   # override automatic GPU detection for this run
```

## ⚠️ Fresh installs only

Run as a regular user. The installer elevates once and that single authorization covers every privileged operation in the run. It is designed for one initial run on a fresh installation, not ongoing system reconciliation.
