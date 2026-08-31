# Arch

## Prerequisites

- A fresh, minimal Arch install (base system only) with [Limine](https://github.com/limine-bootloader/limine) as the bootloader.
- Use btrfs for `/` if you want this repository to configure Snapper pre-upgrade snapshots. The snapshot module is skipped on other filesystems.
- Graphics drivers are selected from every detected display GPU, including hybrid laptops. Intel and AMD use the kernel and Mesa stack. Turing and newer NVIDIA GPUs use Arch's open driver packages, while older supported NVIDIA GPUs use the 580xx AUR packages.
- Set up printing in `archinstall` if you need it. This repository deliberately
  does not install or configure a separate CUPS printing stack on Arch.
- Wi-Fi uses Arch's kernel drivers, `linux-firmware`, and NetworkManager's
  `wpa_supplicant` backend; no vendor-specific driver is selected by this repo.
- A regular user with sudo/network access, then run the installer from the repo root.
