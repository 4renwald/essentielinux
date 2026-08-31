# facile-linux

```text
                                                              ▄▄                ▄▄             ▄▄
 ██             ▀▀  ██             ██ ▀▀
▀██▀ ▀▀█▄ ▄████ ██  ██ ▄█▀█▄       ██ ██  ████▄ ██ ██ ██ ██
 ██ ▄█▀██ ██    ██  ██ ██▄█▀ ▀▀▀▀▀ ██ ██  ██ ██ ██ ██  ███
 ██ ▀█▄██ ▀████ ██▄ ██ ▀█▄▄▄       ██ ██▄ ██ ██ ▀██▀█ ██ ██

 ◆  Fedora · Hyprland · Noctalia
 ◆  Arch · Hyprland · Caelestia
```

One installer for my Fedora and Arch machines. It detects the running distro, then applies that distro's modules, package lists, system files, and dotfiles — a native Hyprland desktop on either side, with Noctalia on Fedora and Caelestia on Arch.

The two distros never share a config file. Everything distro-specific lives under `distros/<id>/`; only the installer engine, menus, and helper functions are shared. Same commands, same menus, same behavior on both.

## 🚀 Quick start

On a fresh machine (no cloning needed):

```bash
curl -fsSL https://raw.githubusercontent.com/4renwald/facile-linux/main/bootstrap.sh | bash
```

The bootstrap installs `git` through the detected distro's package manager, clones the repository to `~/facile-linux`, and starts the interactive installer.

Prefer doing it by hand:

```bash
git clone https://github.com/4renwald/facile-linux.git
cd facile-linux
./install.sh
reboot
```

Run as a regular user. The installer elevates once via `sudo` (falling back to graphical `pkexec` prompts if `sudo` is unavailable or declined) and that single authorization covers every privileged operation in the run.

## 🧭 Usage

```bash
./install.sh                # interactive: GPU, steps, package customization
./install.sh 20 30 55       # run specific steps only
./install.sh --list         # list the detected distro's steps
./install.sh --gpu amd 20   # force a GPU vendor for this run
./install.sh --customize    # edit package selections, run nothing
./install.sh --customize=core
```

Interactive mode walks through two menus:

1. **GPU vendor** — hardware is detected and preselected; override it for hybrid laptops, or pick `none` on VMs. The choice is remembered per machine, so individual steps can be rerun afterwards without being asked again.
2. **Steps** — toggle exactly what this machine should get. Everything is selected by default.

Valid GPU values: `nvidia`, `amd`, `intel`, `none`. Override non-interactively with `--gpu` or `WORKSTATION_GPU`.

## 🧩 Package-level customization

Every package group can be edited before installing:

- The **`📦 Customize packages`** row at the bottom of the step menu opens a browser over all package groups, with the number of deselected packages shown per group.
- `c` on a highlighted step customizes just that step.
- `./install.sh --customize` does the same without running anything.

Inside a group, every package is listed with a one-line description, so you always know what you are switching off. Structural packages (Hyprland itself, PipeWire's core, the NVIDIA kernel module) are marked `· required` and locked. `space` toggles, `a` selects all/none, `r` resets, `enter` applies, `q` cancels.

Choices are stored per machine as small *deselected* lists under `~/.local/state/workstation/<distro>/selections/`. Only what you switched off is recorded — packages added to the repository later are installed by default, and the same choices apply to direct runs.

## 🧩 Steps

**Fedora**

| # | Step | Installs |
| --- | --- | --- |
| 00 | Preflight | Verifies Fedora, x86_64, and required tooling |
| 10 | Repositories | RPM Fusion, COPR, vendor repositories, Flathub |
| 15 | Minimal cleanup | Removes conflicting and superseded packages |
| 20 | Base packages | System update; core, desktop, shell, apps, GPU driver |
| 25 | Audio | PipeWire, WirePlumber, EasyEffects, Bluetooth codecs |
| 26 | Gaming | Steam, GameMode, MangoHud, GOverlay, Gamescope, NTSYNC, Wine |
| 27 | Printing | CUPS, HPLIP, Gutenprint |
| 30 | Upstream & Flatpak | Upstream CLIs, fonts, cursor, mpv shader pack, vendor RPMs, Flathub apps |
| 35 | Wallpapers | Sparse-clones the kept categories of `dharmx/walls` to `~/Pictures/Wallpapers` |
| 40 | System | zram, VM tunables, services, Snapper, Fish login shell |
| 50 | Dotfiles | Hyprland, Noctalia, Ghostty, terminal, Thunar, GTK configuration |
| 55 | Video pipeline | mpv shader link, ff2mpv host, Zen decoding preferences |
| 60 | Greeter | greetd and the Noctalia Greeter login screen |

**Arch**

| # | Step | Installs |
| --- | --- | --- |
| 00 | Base system | Multilib, pacman options, system update, build tools, paru |
| 10 | Packages | Core, desktop, apps, audio, and shell package groups |
| 20 | GPU drivers | CPU microcode and the GPU driver stack |
| 25 | Gaming & AUR | Steam, GameMode, Gamescope, and the AUR application set |
| 30 | Services | zram, VM tunables, system and user services |
| 35 | Snapshots | btrfs pre-upgrade snapshots through snapper and snap-pac |
| 40 | Greeter | greetd, the sysc-greet niri session, and the greeter account |
| 45 | Caelestia | Caelestia shell installer, wallpapers, and managed overrides |
| 50 | Dotfiles | Hyprland, terminal, and agent configuration into `~` |
| 52 | Video pipeline | mpv shader link, ff2mpv host, Zen decoding preferences |
| 55 | Limine boot | Limine bootloader palette and named firmware entry |

After an Arch install, reboot and run `distros/arch/check.sh` from a Hyprland session to verify the result.

## 🎨 GPU support

Step 20 installs one driver stack, chosen by detection, menu, `--gpu`, or `WORKSTATION_GPU`:

| Vendor | Fedora | Arch |
| --- | --- | --- |
| NVIDIA | RPM Fusion open kernel module (akmod), built and verified during the step | Open kernel modules matched to the installed kernel; conflicts detected before installing |
| AMD | Mesa VA-API/VDPAU userspace | Mesa, Vulkan Radeon, lib32 variants |
| Intel | intel-media-driver plus legacy VA-API | Mesa, Vulkan Intel, intel-media-driver |
| none | — | VMs and headless machines; skips the GPU stack entirely |

Hybrid laptops are detected as ambiguous; pick the GPU that should drive the desktop.

## 📦 What is included?

| Area | Fedora | Arch |
| --- | --- | --- |
| Shell | Noctalia Shell v5, Noctalia Greeter | Caelestia Shell, sysc-greet |
| Terminal | Fish, Starship, Fastfetch, direnv, eza, zoxide, fzf, fd, ripgrep, bat | Fish, Starship, eza, zoxide, fzf, fd, ripgrep, bat |
| Gaming | Steam, GameMode, MangoHud, GOverlay, Gamescope, NTSYNC, Protontricks, vkBasalt, Wine | Steam, GameMode, MangoHud, GOverlay, Gamescope, NTSYNC, Protontricks, vkBasalt |
| Applications | Brave, Zen, VSCodium, Discord, Signal, Telegram, Obsidian, Spotify, mpv + ff2mpv, QEMU + vm-curator, Claude Code, OpenCode, GitHub/GitLab CLIs | Zen, Helium, Discord, Signal, Telegram, Obsidian, Spotify, mpv + ff2mpv, QEMU + vm-curator, Claude Code, OpenCode, GitHub/GitLab CLIs |
| System | NetworkManager, BlueZ, CUPS, firmware updates, SMART monitoring, zram, Btrfs snapshots | NetworkManager, BlueZ, firmware updates, SMART monitoring, zram, Btrfs snapshots, Limine |

## 🧹 Package policy

Package manifests under `distros/<distro>/packages/` are the authoritative install lists, written as `name :: description` with `*` marking structural packages. Each distro installs from its own sources:

| Requested item | Fedora | Arch |
| --- | --- | --- |
| Core and desktop packages | Fedora and RPM Fusion RPMs; Hyprland via COPR | Arch official repositories |
| Browsers and vendor apps | Vendor RPM repositories, official vendor RPMs, Flathub | AUR through paru (reviewed interactively) |
| CLI tools, fonts, cursor, shader pack | Official upstream releases | Official repositories or AUR |
| Zen, Spotify, Signal, Obsidian | System-wide Flathub applications | AUR packages |

## ✨ First run

- With NVIDIA, reboot after the driver finishes building before judging its health; on Fedora the akmod build is verified during step 20 (`modinfo -F version nvidia`).
- Open Spotify once before running `spicetify`, and run `claude` once to complete its sign-in.
- Install the ff2mpv add-on from [addons.mozilla.org](https://addons.mozilla.org/firefox/addon/ff2mpv/) in Zen; the native messaging host is ready for it once the video step has run.
- Fedora: choose the final palette and wallpaper in Noctalia, then use **Security → Noctalia Greeter → Sync Now**.
- Arch: set `editor` in `~/.config/caelestia/hypr-vars.lua` to whichever VS Code build you installed; confirm Above 4G Decoding and Resizable BAR in firmware; enable IOMMU in firmware and on the kernel command line before vm-curator can pass a GPU through.

Existing managed dotfiles are backed up before replacement. Re-running the installer, in whole or by step, is supported.

## 📁 Layout

```
workstation/
├── install.sh               # entry point: detects the distro, runs the engine
├── bootstrap.sh             # git + clone + install.sh, for fresh machines
├── lib/
│   ├── common.sh            # logging, elevation, GPU, manifests, selections
│   ├── menu.sh              # terminal menus and the banner
│   └── engine.sh            # pickers, package customization, module runner
└── distros/
    ├── fedora/
    │   ├── catalogue.sh     # step list, package groups, GPU mapping
    │   ├── modules/         # numbered setup steps
    │   ├── packages/        # package manifests
    │   ├── etc/             # system files
    │   └── dotfiles/        # home directory files
    └── arch/
        └── …                # same structure, plus check.sh
```

A distro is defined entirely by its `distros/<id>/` directory: a `catalogue.sh` declaring its steps and package groups, plus `modules/`, `packages/`, `etc/`, and `dotfiles/`. Adding another distro means adding one directory — the installer picks it up from `/etc/os-release` and everything else follows.
