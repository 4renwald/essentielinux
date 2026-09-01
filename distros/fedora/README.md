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
