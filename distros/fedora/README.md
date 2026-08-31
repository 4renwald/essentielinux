# Fedora

## Prerequisites

- A fresh install from the [Fedora Everything net install ISO](https://fedoraproject.org/everything). This repository is designed for one initial setup run, not ongoing system reconciliation.
- In **Software Selection**:
  - Base environment: **Fedora Custom Operating System**
  - Add-ons: **Standard** and **Common NetworkManager Submodules** (leave everything else off)
- A regular user with sudo/network access, then run the installer from the repo root.

The Fedora installer keeps Wi-Fi vendor-neutral: Fedora's kernel modules are
installed together with the official `hardware-support` firmware group, and
the kernel selects the matching driver automatically from the detected device.
