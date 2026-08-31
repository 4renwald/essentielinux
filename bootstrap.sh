#!/usr/bin/env bash
set -euo pipefail

readonly REPO_URL="https://github.com/4renwald/facile-linux.git"
readonly TARGET_DIR="${WORKSTATION_DIR:-${HOME}/facile-linux}"

if [[ ${EUID} -eq 0 ]]; then
  printf 'Error: run this script as your regular user, without sudo.\n' >&2
  exit 1
fi

if [[ ! -r /etc/os-release ]]; then
  printf 'Error: unable to identify the operating system.\n' >&2
  exit 1
fi

# The bootstrap only needs git, and it needs it through the detected distro's
# package manager.
distro="$(bash -c '. /etc/os-release 2>/dev/null; printf %s "${ID:-}"')"
case ${distro} in
  arch)
    command -v sudo >/dev/null 2>&1 || {
      printf 'Error: sudo is required and must be configured for this user.\n' >&2
      exit 1
    }
    sudo pacman -Syu --needed --noconfirm git
    ;;
  fedora)
    command -v sudo >/dev/null 2>&1 || {
      printf 'Error: sudo is required and must be configured for this user.\n' >&2
      exit 1
    }
    sudo dnf -y install git
    ;;
  *)
    printf 'Error: this bootstrap supports Arch Linux and Fedora only (found: %s).\n' "${distro}" >&2
    exit 1
    ;;
esac

if [[ -e "${TARGET_DIR}" ]]; then
  printf 'Error: %s already exists. This bootstrap is for a fresh checkout; choose a different WORKSTATION_DIR.\n' "${TARGET_DIR}" >&2
  exit 1
else
  git clone "${REPO_URL}" "${TARGET_DIR}"
fi

# When run through `curl | bash`, stdin is the exhausted pipe; reattach the
# terminal so the interactive installer can prompt.
if [[ ! -t 0 ]] && { : < /dev/tty; } 2>/dev/null; then
  exec "${TARGET_DIR}/install.sh" < /dev/tty
fi
exec "${TARGET_DIR}/install.sh"
