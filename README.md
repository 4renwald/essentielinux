# facile-linux

One installer for my Fedora and Arch machines. It detects the running distro, then applies that distro's modules, package lists, system files, and dotfiles — a native Hyprland desktop on either side, with Noctalia on Fedora and Caelestia on Arch.

## 🚀 Quick start

On a fresh machine (no cloning needed):

```bash
curl -fsSL https://raw.githubusercontent.com/4renwald/facile-linux/main/bootstrap.sh | bash
```

Or by hand:

```bash
git clone https://github.com/4renwald/facile-linux.git
cd facile-linux
./install.sh
reboot
```

## 📋 Prerequisites

Each distro needs a specific base install before running the installer:

- **Fedora** — [distros/fedora/README.md](distros/fedora/README.md)
- **Arch** — [distros/arch/README.md](distros/arch/README.md)

## 🧭 Usage

```bash
./install.sh                # interactive: GPU, steps, package customization
./install.sh 20 30 55       # run specific steps only
./install.sh --list         # list the detected distro's steps
./install.sh --gpu amd 20   # force a GPU vendor for this run
```

Run as a regular user. The installer elevates once and that single authorization covers every privileged operation in the run. It is designed for one initial run on a fresh installation, not ongoing system reconciliation.
