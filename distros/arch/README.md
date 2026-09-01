# Arch

## Prerequisites

- A fresh, minimal Arch install (base system only) with [Limine](https://github.com/limine-bootloader/limine) as the bootloader.
- Install `curl` before using the one-line bootstrap command: `pacman -S curl`.
- Use btrfs for `/` if you want this repository to configure Snapper pre-upgrade snapshots. The snapshot module is skipped on other filesystems.
- Graphics drivers are selected from every detected display GPU, including hybrid laptops. Intel and AMD use the kernel and Mesa stack. Turing and newer NVIDIA GPUs use Arch's open driver packages, while older supported NVIDIA GPUs use the 580xx AUR packages.
- Set up printing in `archinstall` if you need it. This repository deliberately
  does not install or configure a separate CUPS printing stack on Arch.
- Wi-Fi uses Arch's kernel drivers, `linux-firmware`, and NetworkManager's
  `wpa_supplicant` backend; no vendor-specific driver is selected by this repo.
- A regular user with sudo/network access, then run the installer from the repo root.

When Caelestia is installed, its app integrations follow the packages you
selected: Code opens with the Caelestia theme, Equibop enables its generated
theme, and Spicetify applies its Spotify theme. Spotify needs no manual first
launch: the installer creates the `prefs` file Spicetify insists on, hands the
Spotify directory to your user so Spicetify can rewrite it, and takes the
backup Spicetify requires before applying a theme.

The Limine step themes every `limine.conf` it finds, since which one Limine
reads depends on how the firmware reports the volume it booted from. It adds a
named firmware entry only when no existing entry already boots the same loader,
so the entry `archinstall` created ("Arch Linux Limine Bootloader") is kept
rather than duplicated.

## Toolchains, WinBoat, and Tailscale

Both distributions install the same four additions, each as its own
deselectable package group:

- **Python 3 and uv** — uv is the entry point: it manages interpreters, virtual
  environments, and project dependencies.
- **Go** — the standard toolchain.
- **WinBoat** — runs Windows applications on the Linux desktop. It boots
  Windows in a container and connects over RDP, so the host also gets Docker
  Engine, the Compose v2 plugin, and a FreeRDP 3 client. The installer enables
  `docker.service` and adds you to the `docker` group, which WinBoat checks for
  at startup. **Docker group membership is root-equivalent on this machine**:
  anyone in it can start a privileged container. It takes effect at your next
  login. WinBoat also needs KVM, so virtualization must be enabled in firmware.
- **Tailscale** — the client and `tailscaled`, enabled but logged out. Joining
  a tailnet authenticates this machine, so that stays a deliberate step:

  ```bash
  sudo tailscale up
  ```
