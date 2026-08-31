#!/usr/bin/env bash
set -Eeuo pipefail

readonly DISTRO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT="$(cd -- "${DISTRO_ROOT}/../.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"

log_step 'Installing printing packages'
install_dnf_manifest "${DISTRO_ROOT}/packages/printing.txt"

log_step 'Enabling the CUPS socket activation'
as_root systemctl enable --now cups.socket

log_success 'CUPS, HPLIP, and Gutenprint are configured.'
