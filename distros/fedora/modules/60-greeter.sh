#!/usr/bin/env bash
set -Eeuo pipefail

readonly DISTRO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT="$(cd -- "${DISTRO_ROOT}/../.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"

require_command noctalia-greeter-session

log_step 'Preparing the Noctalia Greeter system account'
if ! id greeter >/dev/null 2>&1; then
  nologin_path="$(command -v nologin)" || die 'nologin is unavailable.'
  as_root useradd --system --user-group --create-home \
    --home-dir /var/lib/noctalia-greeter --shell "${nologin_path}" greeter
fi
greeter_uid="$(id -u greeter)"
(( greeter_uid < 1000 )) || die "Refusing to repurpose non-system account greeter (UID ${greeter_uid})."
getent group greeter >/dev/null 2>&1 || die 'The greeter system group is missing.'
as_root usermod -d /var/lib/noctalia-greeter greeter
as_root install -d --mode=0755 --owner=greeter --group=greeter \
  /var/lib/noctalia-greeter \
  /var/lib/noctalia-greeter/.config \
  /var/lib/noctalia-greeter/.local/state

deploy_system_file "${DISTRO_ROOT}/etc/greetd/config.toml" /etc/greetd/config.toml

if [[ -x /usr/share/noctalia-greeter/setup_greeter_system.sh ]]; then
  as_root /usr/share/noctalia-greeter/setup_greeter_system.sh
elif [[ -x /usr/share/noctalia-greeter/setup_greetd_pam.sh ]]; then
  as_root /usr/share/noctalia-greeter/setup_greetd_pam.sh
else
  die 'Noctalia Greeter did not ship its supported system or PAM setup executable.'
fi

as_root systemctl set-default graphical.target
as_root systemctl enable greetd.service
log_success 'greetd will start Noctalia Greeter on the next boot.'
