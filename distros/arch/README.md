# Arch

## Prerequisites

- A fresh, minimal Arch install (base system only) with [Limine](https://github.com/limine-bootloader/limine) as the bootloader.
- Use btrfs for `/` if you want this repository to configure Snapper pre-upgrade snapshots. The snapshot module is skipped on other filesystems.
- Set up printing in `archinstall` if you need it. This repository deliberately
  does not install or configure a separate CUPS printing stack on Arch.
- A regular user with sudo/network access, then run the installer from the repo root.
