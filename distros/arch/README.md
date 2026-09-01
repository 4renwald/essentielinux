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
backup Spicetify requires before applying a theme. Zen gets the CaelestiaFox
extension through its Firefox policy and the required `userChrome.css` profile
preference, so there is no browser setup click. If Zen has no profile yet, the
installer starts it headlessly once to create one.

The Limine step themes every `limine.conf` it finds, since which one Limine
reads depends on how the firmware reports the volume it booted from. It adds a
named firmware entry only when no existing entry already boots the same loader,
so the entry `archinstall` created ("Arch Linux Limine Bootloader") is kept
rather than duplicated.
