#!/usr/bin/env bash
set -uo pipefail

readonly DISTRO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd -- "${DISTRO_ROOT}/../.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"
readonly CAELESTIA_EXECS_PATCH="${DISTRO_ROOT}/etc/caelestia/execs-night-light.patch"

failures=0
warnings=0

pass() { log_success "$*"; }
fail() { log_error "$*"; failures=$((failures + 1)); }
warn() { log_warn "$*"; warnings=$((warnings + 1)); }

check_command() {
  if command -v "$1" >/dev/null 2>&1; then pass "Command available: $1"; else fail "Missing command: $1"; fi
}

check_package() {
  if pacman -Q "$1" >/dev/null 2>&1; then pass "Package installed: $1"; else fail "Missing package: $1"; fi
}

caelestia_component_enabled() {
  local component=$1 state_file="${XDG_STATE_HOME:-${HOME}/.local/state}/caelestia/dots-state.json"
  [[ -f ${state_file} ]] \
    && jq -e --arg component "${component}" \
      '.enabled_components | type == "array" and index($component) != null' \
      "${state_file}" >/dev/null 2>&1
}

check_enabled() {
  if systemctl is-enabled --quiet "$1"; then pass "Service enabled: $1"; else fail "Service not enabled: $1"; fi
}

check_user_enabled() {
  if systemctl --user is-enabled --quiet "$1"; then pass "User service enabled: $1"; else fail "User service not enabled: $1"; fi
}

deployed_hypr_file_matches() {
  local source_file=$1 relative_file=$2 target_file=$3 expected_file status=0

  if [[ ${relative_file} != hyprland/execs.lua ]]; then
    cmp -s -- "${source_file}" "${target_file}"
    return
  fi
  [[ -r ${CAELESTIA_EXECS_PATCH} ]] || return 1

  expected_file="$(mktemp "${TMPDIR:-/tmp}/workstation-check-caelestia-XXXXXX")"
  cp -- "${source_file}" "${expected_file}"
  patch --silent --fuzz=0 --no-backup-if-mismatch "${expected_file}" "${CAELESTIA_EXECS_PATCH}" \
    || status=$?
  if [[ ${status} -eq 0 ]]; then
    cmp -s -- "${expected_file}" "${target_file}" || status=$?
  fi
  rm -f -- "${expected_file}"
  return "${status}"
}

log_step "Essential commands"
for command in paru Hyprland start-hyprland qs caelestia jq ghostty fuzzel zen-browser helium-browser gh glab wpctl grim slurp wl-copy cliphist lspci steam gamescope goverlay mangohud gamemoderun vulkaninfo vainfo zramctl \
  mpv yt-dlp \
  gammastep notify-send gnome-keyring-daemon trash-empty dconf xdg-settings man protontricks vm-curator qemu-system-x86_64 \
  claude codex opencode opencode-desktop code \
  sysc-greet niri kitty; do
  check_command "${command}"
done

log_step "Operating system"
if [[ -r /etc/os-release ]] && grep -Eq '^ID=(arch|"arch")$' /etc/os-release; then
  pass "Arch Linux detected."
else
  fail "This installation is not running on Arch Linux."
fi

if pacman-conf --repo-list 2>/dev/null | grep -Fxq multilib; then
  pass "Arch multilib repository enabled."
else
  fail "Arch multilib repository is disabled. Run ./install.sh 00."
fi

hyprland_version="$(pacman -Q hyprland 2>/dev/null | awk 'NF >= 2 { print $2; exit }')"
if [[ -n ${hyprland_version} ]] && command -v vercmp >/dev/null 2>&1 \
  && [[ $(vercmp "${hyprland_version}" 0.55.0) -ge 0 ]]; then
  pass "Hyprland ${hyprland_version} supports Caelestia's native Lua configuration."
else
  fail "Caelestia requires Hyprland 0.55 or newer; installed version: ${hyprland_version:-missing}."
fi

log_step "Declared package sets"
for group in base desktop apps audio shell gaming aur; do
  read_manifest "${DISTRO_ROOT}/packages/${group}.txt"
  for package in "${PACKAGES[@]}"; do
    check_package "${package}"
  done
done
check_package base-devel
check_package paru

paru_path="$(command -v paru 2>/dev/null || true)"
paru_owner=''
if [[ -n ${paru_path} ]]; then
  paru_owner="$(pacman -Qqo "${paru_path}" 2>/dev/null || true)"
fi
if [[ -n ${paru_path} && ${paru_owner} == paru ]] && paru --version >/dev/null 2>&1; then
  pass "The active paru executable is owned by the reviewed paru package and starts correctly."
else
  fail "The active paru executable is missing, broken, or owned by '${paru_owner:-no package}'. Run ./install.sh 00."
fi

check_package mangohud

log_step "Terminal theming"
fish_path="$(command -v fish 2>/dev/null || true)"
login_shell="$(getent passwd "$(id -un)" | cut -d: -f7)"
if [[ -n ${fish_path} && ${login_shell} == "${fish_path}" ]]; then
  pass "fish is the login shell, so terminals replay Caelestia's scheme."
else
  fail "The login shell is ${login_shell:-unknown}, not fish; terminals will keep their own colours. Run ./install.sh 50."
fi

fish_config="${HOME}/.config/fish/config.fish"
if [[ -f ${fish_config} ]] && grep -Fq 'caelestia/sequences.txt' "${fish_config}"; then
  pass "Caelestia's fish config replays the scheme escape sequences."
else
  fail "${fish_config} does not replay caelestia/sequences.txt. Run ./install.sh 45 and select the fish component."
fi

ghostty_config="${HOME}/.config/ghostty/config"
if [[ -f ${ghostty_config} ]] && ! path_has_symlink "${ghostty_config}"; then
  pass "The Ghostty configuration is deployed."
else
  fail "Missing or linked Ghostty configuration: ${ghostty_config}. Run ./install.sh 50."
fi

log_step "Keybind cheatsheet"
keybinds_script="${HOME}/.local/bin/hypr-keybinds"
if [[ -x ${keybinds_script} ]] && ! path_has_symlink "${keybinds_script}"; then
  pass "The keybind cheatsheet script is deployed and executable."
else
  fail "Missing, linked or non-executable: ${keybinds_script}. Run ./install.sh 50."
fi

caelestia_conf="${HOME}/.config/caelestia"
if grep -Fq 'hypr-keybinds' "${caelestia_conf}/hypr-user.lua" 2>/dev/null; then
  pass "SUPER + K is bound to the keybind cheatsheet."
else
  fail "${caelestia_conf}/hypr-user.lua does not bind the cheatsheet. Run ./install.sh 50."
fi

if grep -Fq 'kbShowPanels' "${caelestia_conf}/hypr-vars.lua" 2>/dev/null; then
  pass "Caelestia's show-panels bind is moved off SUPER + K."
else
  fail "${caelestia_conf}/hypr-vars.lua does not move kbShowPanels, so SUPER + K is bound twice. Run ./install.sh 50."
fi

if grep -Eq 'browser[[:space:]]*=[[:space:]]*"helium-browser"' "${caelestia_conf}/hypr-vars.lua" 2>/dev/null; then
  pass "Caelestia's browser keybind launches Helium, the default browser."
else
  fail "${caelestia_conf}/hypr-vars.lua does not point Caelestia's browser keybind at helium-browser. Run ./install.sh 50."
fi

log_step "Proton builds"
steam_data_dir=''
for candidate in \
  "${HOME}/.steam/steam" \
  "${HOME}/.steam/root" \
  "${XDG_DATA_HOME:-${HOME}/.local/share}/Steam"; do
  if [[ -d ${candidate} ]]; then
    steam_data_dir="${candidate}"
    break
  fi
done
steam_data_dir="${steam_data_dir:-${XDG_DATA_HOME:-${HOME}/.local/share}/Steam}"
compat_dir="${steam_data_dir}/compatibilitytools.d"
proton_ge_dir="$(find "${compat_dir}" -maxdepth 1 -mindepth 1 -type d -name 'GE-Proton*' 2>/dev/null | sort -V | tail -n1)"
# ProtonPlus installs these on demand, so none being present is a state to
# report rather than an installation failure.
if [[ -n ${proton_ge_dir} && -x ${proton_ge_dir}/proton ]]; then
  pass "Proton-GE available to Steam: ${proton_ge_dir##*/}"
elif [[ -n ${proton_ge_dir} ]]; then
  fail "${proton_ge_dir} has no runnable proton script. Remove it and add a build again with ProtonPlus."
else
  warn "No Proton build in ${compat_dir}. Open ProtonPlus and add one."
fi

log_step "Caelestia packages"
check_package caelestia-shell

# Quickshell arrives as a dependency of caelestia-shell. Check that it runs
# rather than which package name provides it, so this keeps working if the
# dependency moves between the AUR and the official repositories.
if command -v qs >/dev/null 2>&1; then
  if quickshell_version="$(qs --version 2>&1)"; then
    pass "Quickshell starts: ${quickshell_version//$'\n'/; }"
  else
    fail "Quickshell cannot start. Clean-rebuild Quickshell and caelestia-shell against the current system libraries."
  fi
else
  fail "No qs executable found. Run ./install.sh 45."
fi

caelestia_plugin=''
while IFS= read -r package_file; do
  if [[ ${package_file} == */libcaelestia-servicesplugin.so ]]; then
    caelestia_plugin=${package_file}
    break
  fi
done < <(pacman -Qlq caelestia-shell 2>/dev/null)
if [[ -n ${caelestia_plugin} && -f ${caelestia_plugin} ]]; then
  ldd_ok=true
  if ldd_output="$(ldd "${caelestia_plugin}" 2>&1)"; then
    missing_libraries="$(awk '/not found/ { print $1 }' <<< "${ldd_output}")"
  else
    ldd_ok=false
    missing_libraries=''
    fail "Unable to inspect Caelestia shell plugin dependencies: ${ldd_output//$'\n'/; }"
  fi
  if [[ -n ${missing_libraries} ]]; then
    fail "Caelestia shell plugin has missing libraries: ${missing_libraries//$'\n'/, }. Clean-rebuild caelestia-shell."
  elif [[ ${ldd_ok} == true ]]; then
    pass "Caelestia shell plugin dependencies resolve."
  fi
else
  fail "Unable to locate the installed Caelestia shell plugin."
fi

log_step "Cursor theme"
if [[ -d /usr/share/icons/Bibata-Modern-Classic ]]; then
  pass "Bibata-Modern-Classic is installed."
else
  fail "Bibata-Modern-Classic is missing from /usr/share/icons."
fi

log_step "System services"
for service in NetworkManager.service bluetooth.service accounts-daemon.service power-profiles-daemon.service fstrim.timer greetd.service \
  paccache.timer reflector.timer fwupd-refresh.timer smartd.service; do
  check_enabled "${service}"
done

log_step "Agent privilege prompts"
check_command pkexec
# polkit-gnome ships no systemd user unit. Caelestia's execs.lua starts the
# agent by absolute path, and hl.exec_cmd failures are silent, so check the
# binary rather than a service.
polkit_agent=/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
if [[ -x ${polkit_agent} ]]; then
  pass "The Polkit agent Caelestia starts is installed: ${polkit_agent}"
else
  fail "Missing ${polkit_agent}; graphical authentication prompts would do nothing. Run ./install.sh 10."
fi
if pgrep -u "$(id -u)" -f "${polkit_agent}" >/dev/null 2>&1; then
  pass "A Polkit authentication agent is running."
else
  warn "No Polkit authentication agent is running. Expected when running outside a Hyprland session."
fi

log_step "Memory and storage policy"
if cmp -s -- "${DISTRO_ROOT}/etc/systemd/zram-generator.conf" /etc/systemd/zram-generator.conf \
  && cmp -s -- "${DISTRO_ROOT}/etc/sysctl.d/99-arch-config.conf" /etc/sysctl.d/99-arch-config.conf; then
  pass "The version-controlled zram policy is deployed."
else
  fail "The zram or VM policy differs from the repository. Run ./install.sh 30."
fi
if systemctl is-active --quiet systemd-zram-setup@zram0.service \
  && swapon --noheadings --show=NAME 2>/dev/null | grep -Fxq /dev/zram0; then
  pass "Compressed swap is active on /dev/zram0."
else
  fail "Compressed swap is not active on /dev/zram0. Run ./install.sh 30, then reboot."
fi
if [[ $(sysctl -n vm.swappiness 2>/dev/null) == 100 \
  && $(sysctl -n vm.page-cluster 2>/dev/null) == 0 ]]; then
  pass "The zram-aware VM policy is active."
else
  fail "The expected VM policy is not active. Run ./install.sh 30."
fi

if ! path_has_symlink /etc/greetd/config.toml \
  && grep -Fq -- 'niri -c /etc/greetd/niri-greeter-config.kdl' /etc/greetd/config.toml 2>/dev/null; then
  pass "greetd starts sysc-greet inside its niri greeter session."
else
  fail "greetd is not configured to start the sysc-greet niri session. Run ./install.sh 40."
fi

# The greeter is useless if the compositor config points at a binary that is
# not there: the screen simply stays blank at boot.
sysc_greet_path="$(command -v sysc-greet 2>/dev/null || true)"
if [[ -n ${sysc_greet_path} ]] \
  && grep -Fq "${sysc_greet_path}" /etc/greetd/niri-greeter-config.kdl 2>/dev/null; then
  pass "The niri greeter configuration runs the installed sysc-greet (${sysc_greet_path})."
else
  fail "/etc/greetd/niri-greeter-config.kdl does not run the installed sysc-greet. Run ./install.sh 40."
fi

if [[ -f /etc/greetd/kitty.conf ]]; then
  pass "The greeter's kitty configuration is present."
else
  fail "/etc/greetd/kitty.conf is missing; the greeter cannot start. Reinstall sysc-greet."
fi

greeter_home="$(getent passwd greeter 2>/dev/null | cut -d: -f6)"
if [[ ${greeter_home} == /var/lib/greeter ]]; then
  pass "The greeter account uses the home sysc-greet expects."
else
  fail "The greeter home is '${greeter_home:-missing}', not /var/lib/greeter. Run ./install.sh 40."
fi

greeter_groups_ok=true
for greeter_group in video render input; do
  id -nG greeter 2>/dev/null | tr ' ' '\n' | grep -Fxq "${greeter_group}" || greeter_groups_ok=false
done
if [[ ${greeter_groups_ok} == true ]]; then
  pass "The greeter account is in the video, render and input groups."
else
  fail "The greeter account is missing video, render or input group membership. Run ./install.sh 40."
fi

if [[ -f /etc/polkit-1/rules.d/85-greeter.rules ]]; then
  pass "The greeter may shut down and reboot through polkit."
else
  warn "/etc/polkit-1/rules.d/85-greeter.rules is missing; shutdown and reboot from the login screen will be denied."
fi

log_step "User configuration"
wallpaper_dir="${HOME}/Pictures/Wallpapers"
wallpaper_repository='https://github.com/dharmx/walls.git'
wallpaper_origin="$(git -C "${wallpaper_dir}" remote get-url origin 2>/dev/null || true)"
if [[ -d ${wallpaper_dir}/.git && ${wallpaper_origin%.git} == ${wallpaper_repository%.git} ]]; then
  pass "Caelestia wallpapers are cloned at ${wallpaper_dir}."
else
  fail "Caelestia wallpaper repository is missing or has the wrong origin at ${wallpaper_dir}. Run ./install.sh 45."
fi

# Module 45 sparse-clones dharmx/walls and cherry-picks only these category
# folders, so the rest of the upstream repository is never fetched. The
# sparse-checkout selection is reapplied on every run of module 45.
wallpaper_kept_categories=(
  abstract animated anime apeiros calm centered chillop devicons digital
  dreamcore evangelion gruvbox m-26.jp minimal mountain nature nord outrun
  painting pixel radium spam stalenhag tile unsorted
)
wallpaper_missing_categories=()
for wallpaper_category in "${wallpaper_kept_categories[@]}"; do
  [[ -d ${wallpaper_dir}/${wallpaper_category} ]] \
    || wallpaper_missing_categories+=("${wallpaper_category}")
done
if [[ -d ${wallpaper_dir} && ${#wallpaper_missing_categories[@]} -gt 0 ]]; then
  fail "Sparse checkout is missing wallpaper categories: ${wallpaper_missing_categories[*]}. Run ./install.sh 45."
elif [[ -d ${wallpaper_dir} ]]; then
  pass "Every kept wallpaper category is checked out at ${wallpaper_dir}."
fi

state_home="${XDG_STATE_HOME:-${HOME}/.local/state}"
hypr_config_dir="${HOME}/.config/hypr"
hypr_main_config="${hypr_config_dir}/hyprland.lua"
hypr_execs_config="${hypr_config_dir}/hyprland/execs.lua"
caelestia_state_file="${state_home}/caelestia/dots-state.json"
caelestia_dots_dir="${state_home}/caelestia/dots"
hypr_execs_require_pattern="require[[:space:]]*\\([[:space:]]*['\"]hyprland\\.execs['\"][[:space:]]*\\)"
hypr_start_event_pattern="hl\\.on[[:space:]]*\\([[:space:]]*['\"]hyprland\\.start['\"]"
caelestia_autostart_pattern="hl\\.exec_cmd[[:space:]]*\\([[:space:]]*['\"]caelestia[[:space:]]+shell[[:space:]]+-d['\"][[:space:]]*\\)"
caelestia_ok=true
for required_file in \
  "${hypr_main_config}" \
  "${hypr_config_dir}/hyprland/keybinds.lua" \
  "${hypr_execs_config}"; do
  if [[ ! -f ${required_file} ]] || path_has_symlink "${required_file}"; then
    fail "Missing or linked Caelestia config: ${required_file}"
    caelestia_ok=false
  fi
done
if [[ ${caelestia_ok} == true ]]; then
  linked_hypr_config="$(find "${hypr_config_dir}" -type l -print -quit)"
  if [[ -n ${linked_hypr_config} ]]; then
    fail "Linked file found in the Caelestia Hyprland config: ${linked_hypr_config}"
  else
    pass "The Caelestia Hyprland configuration is deployed as real files."
  fi

  if grep -Eq "${hypr_execs_require_pattern}" "${hypr_main_config}"; then
    pass "Hyprland loads Caelestia's startup module."
  else
    fail "${hypr_main_config} does not load hyprland.execs. Run ./install.sh 45."
  fi

  if grep -Eq "${hypr_start_event_pattern}" "${hypr_execs_config}" \
    && grep -Eq "${caelestia_autostart_pattern}" "${hypr_execs_config}"; then
    pass "Caelestia shell autostart is registered for hyprland.start."
  else
    fail "${hypr_execs_config} does not contain the required Caelestia shell autostart callback. Run ./install.sh 45."
  fi

  if grep -Fq 'vars.automaticNightLight ~= false' "${hypr_execs_config}" \
    && grep -Eq 'automaticNightLight[[:space:]]*=[[:space:]]*(true|false)' "${caelestia_conf}/hypr-vars.lua" \
    && grep -Fq 'pgrep -x gammastep' "${caelestia_conf}/hypr-user.lua"; then
    pass "Caelestia's automatic night light has a master setting and a SUPER + SHIFT + N toggle."
  else
    fail "Caelestia's managed night-light setting or toggle is missing. Run ./install.sh 45, then ./install.sh 50."
  fi
fi

if [[ -f ${caelestia_state_file} ]] && command -v jq >/dev/null 2>&1 \
  && jq -e '
    (.applied_rev | type == "string" and length > 0)
    and (.enabled_components | type == "array" and index("hypr") != null)
  ' "${caelestia_state_file}" >/dev/null 2>&1; then
  pass "Caelestia installation state records the Hyprland component."
else
  fail "Caelestia installation state is missing, invalid, or does not enable Hyprland. Run ./install.sh 45."
fi

log_step "Caelestia app integrations"
if caelestia_component_enabled vscode || pacman -Q code >/dev/null 2>&1; then
  code_settings="${HOME}/.config/Code/User/settings.json"
  if [[ -f ${code_settings} ]] \
    && jq -e '."workbench.colorTheme" == "Caelestia"' "${code_settings}" >/dev/null 2>&1; then
    pass 'Code starts with the Caelestia colour theme.'
  else
    fail "Code is not set to the Caelestia colour theme: ${code_settings}. Run ./install.sh 45."
  fi
fi
if caelestia_component_enabled vscodium || pacman -Q vscodium-bin >/dev/null 2>&1; then
  codium_settings="${HOME}/.config/VSCodium/User/settings.json"
  if [[ -f ${codium_settings} ]] \
    && jq -e '."workbench.colorTheme" == "Caelestia"' "${codium_settings}" >/dev/null 2>&1; then
    pass 'VSCodium starts with the Caelestia colour theme.'
  else
    fail "VSCodium is not set to the Caelestia colour theme: ${codium_settings}. Run ./install.sh 45."
  fi
fi
if caelestia_component_enabled discord || pacman -Q equibop-bin >/dev/null 2>&1; then
  equibop_settings="${HOME}/.config/equibop/settings/settings.json"
  equibop_theme="${HOME}/.config/equibop/themes/caelestia.theme.css"
  if [[ -f ${equibop_theme} && -f ${equibop_settings} ]] \
    && jq -e '.enabledThemes | type == "array" and index("caelestia.theme.css") != null' \
      "${equibop_settings}" >/dev/null 2>&1; then
    pass 'Equibop has Caelestia enabled in its local theme list.'
  else
    fail "Equibop is missing the enabled Caelestia theme. Run ./install.sh 45."
  fi
fi
if caelestia_component_enabled spotify \
  || { pacman -Q spotify >/dev/null 2>&1 && pacman -Q spicetify-cli >/dev/null 2>&1; }; then
  spotify_apps_dir="$(pacman -Ql spotify 2>/dev/null \
    | awk '$2 ~ /\/Apps\/$/ { print substr($2, 1, length($2) - 1); exit }')"
  [[ -n ${spotify_apps_dir} ]] || spotify_apps_dir=/opt/spotify/Apps
  if ! command -v spicetify >/dev/null 2>&1 \
    || ! spicetify config current_theme 2>/dev/null | grep -Eq '(^|[[:space:]=])caelestia([[:space:]]|$)'; then
    fail 'Spicetify is not configured for the Caelestia theme. Run ./install.sh 45.'
  # Naming the theme in config-xpui.ini is not the same as having applied it:
  # `spicetify apply` unpacks xpui.spa into an xpui directory and writes the
  # theme's user.css there, so that is what proves Spotify is actually themed.
  elif [[ ! -f ${spotify_apps_dir}/xpui/user.css ]]; then
    fail "Spicetify names the Caelestia theme but has not applied it to ${spotify_apps_dir}. Run ./install.sh 45."
  else
    pass 'Spicetify is using the Caelestia theme.'
  fi
fi
if caelestia_component_enabled zen || pacman -Q zen-browser-bin >/dev/null 2>&1; then
  if [[ -x /usr/lib/caelestia/caelestiafox ]] \
    && [[ -f ${HOME}/.mozilla/native-messaging-hosts/caelestiafox.json ]]; then
    pass 'CaelestiaFox native messaging is available for Zen.'
  else
    fail 'CaelestiaFox native messaging is missing for Zen. Run ./install.sh 45.'
  fi
  zen_profile_roots=()
  for zen_root in "${XDG_CONFIG_HOME:-${HOME}/.config}/zen" "${HOME}/.zen"; do
    [[ -r ${zen_root}/profiles.ini ]] && zen_profile_roots+=("${zen_root}")
  done
  zen_theme_profiles=0
  for zen_root in "${zen_profile_roots[@]}"; do
    profiles_ini="${zen_root}/profiles.ini"
    mapfile -t zen_theme_profile_paths < <(awk -v root="${zen_root}" '
      function flush() {
        if (path != "") { print (relative == "0" ? path : root "/" path) }
        path = ""; relative = "1"
      }
      { sub(/\r$/, "") }
      /^\[/ { flush(); next }
      /^[[:space:]]*Path[[:space:]]*=/ { sub(/^[^=]*=/, ""); path = $0; next }
      /^[[:space:]]*IsRelative[[:space:]]*=/ { sub(/^[^=]*=/, ""); relative = $0; next }
      END { flush() }
    ' "${profiles_ini}")
    for zen_theme_profile in "${zen_theme_profile_paths[@]}"; do
      if [[ -f ${zen_theme_profile}/chrome/userChrome.css ]] \
        && grep -Fqx ':root {' "${zen_theme_profile}/chrome/userChrome.css" \
        && grep -Fq 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);' \
          "${zen_theme_profile}/user.js" 2>/dev/null; then
        zen_theme_profiles=$((zen_theme_profiles + 1))
      fi
    done
  done
  if ((zen_theme_profiles > 0)); then
    pass "Caelestia's Zen stylesheet is enabled in ${zen_theme_profiles} profile(s)."
  else
    warn 'Zen has no themed profile yet; start Zen once and rerun ./install.sh 45.'
  fi
fi

caelestia_tree_ok=true
caelestia_tree_error=''
if [[ -f ${caelestia_state_file} && -d ${caelestia_dots_dir}/.git ]] \
  && command -v jq >/dev/null 2>&1 && command -v git >/dev/null 2>&1; then
  applied_rev="$(jq -er '.applied_rev | select(type == "string" and length > 0)' "${caelestia_state_file}" 2>/dev/null)" || applied_rev=''
  source_rev="$(git -C "${caelestia_dots_dir}" rev-parse HEAD 2>/dev/null)" || source_rev=''
  if [[ -z ${applied_rev} || ${source_rev} != "${applied_rev}" || ! -d ${caelestia_dots_dir}/hypr ]]; then
    caelestia_tree_ok=false
    caelestia_tree_error="Caelestia's saved revision and local source checkout do not match. Run ./install.sh 45."
  else
    found_source_file=false
    while IFS= read -r -d '' source_file; do
      found_source_file=true
      relative_file="${source_file#"${caelestia_dots_dir}"/hypr/}"
      target_file="${hypr_config_dir}/${relative_file}"
      if [[ ! -f ${target_file} ]] || path_has_symlink "${target_file}" \
        || ! deployed_hypr_file_matches "${source_file}" "${relative_file}" "${target_file}"; then
        caelestia_tree_ok=false
        caelestia_tree_error="Caelestia config is missing, linked, or does not match revision ${applied_rev}: ${target_file}"
        break
      fi
    done < <(find "${caelestia_dots_dir}/hypr" -type f -print0)
    [[ ${found_source_file} == true ]] || caelestia_tree_ok=false
  fi
else
  caelestia_tree_ok=false
  caelestia_tree_error="Caelestia's saved source checkout is missing or unreadable. Run ./install.sh 45."
fi
if [[ ${caelestia_tree_ok} == true ]]; then
  pass "The complete Hyprland tree matches Caelestia revision ${applied_rev} plus managed overrides."
else
  fail "${caelestia_tree_error:-The complete managed Hyprland tree cannot be verified. Run ./install.sh 45.}"
fi

if [[ -f ${hypr_main_config} ]] && verify_output="$(Hyprland --verify-config --config "${hypr_main_config}" 2>&1)"; then
  pass "Hyprland accepts Caelestia's explicit Lua entry file."
else
  fail "Hyprland rejects Caelestia's explicit Lua entry file: ${verify_output:-no verifier output}"
fi

repo_dotfiles_ok=true
while IFS= read -r -d '' source_file; do
  relative=${source_file#"${DISTRO_ROOT}/dotfiles/"}
  relative=${relative#*/}
  target="${HOME}/${relative}"
  if [[ ! -f ${target} ]] || path_has_symlink "${target}" || ! cmp -s -- "${source_file}" "${target}"; then
    fail "Dotfile is missing, linked, or differs from the repository copy: ${target}"
    repo_dotfiles_ok=false
  fi
done < <(find "${DISTRO_ROOT}/dotfiles" -type f -print0)
if [[ ${repo_dotfiles_ok} == true ]]; then
  pass "Repository dotfiles are independent physical copies."
fi

if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
  pass "Hyprland session active."

  config_errors="$(hyprctl configerrors 2>&1)"
  config_status=$?
  if [[ ${config_status} -ne 0 ]]; then
    fail "Unable to query Hyprland configuration errors: ${config_errors}"
  elif [[ -n ${config_errors} ]]; then
    fail "Hyprland configuration errors: ${config_errors//$'\n'/; }"
  else
    pass "Hyprland reports no configuration errors."
  fi

  if command -v caelestia >/dev/null 2>&1 && caelestia shell -s >/dev/null 2>&1; then
    pass "Caelestia shell is running and its IPC endpoint responds."
  else
    fail "Caelestia shell is not running or its IPC endpoint is unavailable. Run 'caelestia shell' in a terminal to see the startup error."
  fi

  vrr_mode="$(hyprctl -j getoption misc:vrr 2>/dev/null | jq -r '.int // empty' 2>/dev/null)"
  if [[ ${vrr_mode} == 3 ]]; then
    pass "Hyprland enables VRR for fullscreen game and video content."
  else
    fail "Hyprland's VRR mode is '${vrr_mode:-unavailable}', not content-type mode 3. Run ./install.sh 50."
  fi
else
  warn "This check is not running from a Hyprland session."
  warn "Caelestia runtime and Hyprland configuration errors could not be checked."
fi

for service in pipewire.service pipewire-pulse.service wireplumber.service; do
  if systemctl --user is-active --quiet "${service}"; then
    pass "User service active: ${service}"
  else
    warn "User service inactive: ${service}"
  fi
done

check_user="$(id -un)"
if id -nG "${check_user}" | tr ' ' '\n' | grep -Fxq gamemode; then
  pass "${check_user} belongs to the gamemode group."
else
  fail "${check_user} is not in the gamemode group. Run ./install.sh 30, then log out and back in."
fi

# Installing amd-ucode/intel-ucode is not enough: the blob only reaches the CPU
# if mkinitcpio's `microcode` hook packs it into the early initramfs. That hook
# is in Arch's default HOOKS, but not in older or hand-edited mkinitcpio.conf.
check_microcode_early_load() {
  local vendor_blob=$1 image

  if ! grep -qE '^HOOKS=.*[ (]microcode[ )]' /etc/mkinitcpio.conf 2>/dev/null; then
    fail "The 'microcode' hook is missing from HOOKS in /etc/mkinitcpio.conf, so CPU microcode is not loaded early. Add it and regenerate the initramfs."
    return
  fi

  if ! command -v lsinitcpio >/dev/null 2>&1; then
    warn "lsinitcpio is unavailable; the 'microcode' hook is configured but the packed blob was not verified."
    return
  fi

  for image in /boot/initramfs-linux.img /boot/initramfs-linux-lts.img \
    /boot/initramfs-linux-zen.img /boot/initramfs-linux-hardened.img; do
    [[ -r ${image} ]] || continue
    if lsinitcpio --early "${image}" 2>/dev/null | grep -Fq "${vendor_blob}"; then
      pass "CPU microcode (${vendor_blob}) is packed into $(basename "${image}")."
    else
      fail "${vendor_blob} is missing from the early section of $(basename "${image}"). Regenerate the initramfs."
    fi
  done
}

cpu_vendor="$(awk -F: '/^[[:space:]]*vendor_id[[:space:]]*:/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' /proc/cpuinfo)"
case "${cpu_vendor}" in
  AuthenticAMD)
    check_package amd-ucode
    check_microcode_early_load AuthenticAMD.bin
    scaling_driver="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver 2>/dev/null || true)"
    if [[ ${scaling_driver} == amd-pstate* ]]; then
      pass "AMD P-State is active (${scaling_driver})."
    else
      warn "AMD P-State is not active (driver: ${scaling_driver:-unavailable}); check firmware settings and the current Arch kernel before adding kernel parameters."
    fi
    ;;
  GenuineIntel)
    check_package intel-ucode
    check_microcode_early_load GenuineIntel.bin
    ;;
  *) warn "Unknown CPU vendor '${cpu_vendor:-missing}'; microcode package was not checked." ;;
esac

graphics_devices="$(lspci -nn 2>/dev/null | grep -Ei 'VGA|3D|Display' || true)"
check_package mesa-utils
if grep -Eqi 'Advanced Micro Devices|AMD/ATI|\[1002:' <<< "${graphics_devices}"; then
  log_step "AMD graphics stack"
  for package in mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon; do
    check_package "${package}"
  done
fi

if grep -qi intel <<< "${graphics_devices}"; then
  log_step "Intel graphics stack"
  for package in mesa lib32-mesa vulkan-intel lib32-vulkan-intel intel-media-driver; do
    check_package "${package}"
  done
fi

if grep -qi nvidia <<< "${graphics_devices}"; then
  log_step "NVIDIA driver"
  nvidia_flavor="$(nvidia_kernel_module_flavor 2>/dev/null || true)"
  if [[ -z ${nvidia_flavor} ]]; then
    fail 'NVIDIA is present but its display PCI ID could not be classified.'
    nvidia_flavor=unsupported
  fi
  for package in libva-nvidia-driver; do
    check_package "${package}"
  done

  use_nvidia_dkms=false
  declare -a installed_nvidia_kernels=()
  for kernel in linux linux-lts linux-zen linux-hardened; do
    if pacman -Q "${kernel}" >/dev/null 2>&1; then
      installed_nvidia_kernels+=("${kernel}")
      if [[ ${kernel} == linux-zen || ${kernel} == linux-hardened ]]; then
        use_nvidia_dkms=true
      fi
    fi
  done
  if [[ ${#installed_nvidia_kernels[@]} -eq 0 ]]; then
    fail "No supported Arch kernel is installed for the NVIDIA driver."
  elif [[ ${nvidia_flavor} == proprietary ]]; then
    for package in nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils; do
      check_package "${package}"
    done
    for kernel in "${installed_nvidia_kernels[@]}"; do
      check_package "${kernel}-headers"
    done
  elif [[ ${nvidia_flavor} == unsupported ]]; then
    fail 'This NVIDIA GPU needs a legacy branch older than 580xx. Its driver is not managed by this repository.'
  elif [[ ${use_nvidia_dkms} == true ]]; then
    for package in nvidia-utils lib32-nvidia-utils; do
      check_package "${package}"
    done
    check_package nvidia-open-dkms
    for kernel in "${installed_nvidia_kernels[@]}"; do
      check_package "${kernel}-headers"
    done
  else
    for package in nvidia-utils lib32-nvidia-utils; do
      check_package "${package}"
    done
    for kernel in "${installed_nvidia_kernels[@]}"; do
      case "${kernel}" in
        linux) check_package nvidia-open ;;
        linux-lts) check_package nvidia-open-lts ;;
      esac
    done
  fi
  if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
    pass "nvidia-smi is working."
    if grep -Fqi 'GeForce RTX 4090' <<< "${graphics_devices}"; then
      bar1_total_mib="$(nvidia-smi -q 2>/dev/null | awk '
        /BAR1 Memory Usage/ { in_bar1 = 1; next }
        in_bar1 && /Total/ { print $(NF - 1); exit }
      ')"
      if [[ ${bar1_total_mib} =~ ^[0-9]+$ && ${bar1_total_mib} -ge 1024 ]]; then
        pass "The RTX 4090 exposes ${bar1_total_mib} MiB of BAR1 space; Resizable BAR is available."
      else
        warn "The RTX 4090 exposes only ${bar1_total_mib:-an unknown amount of} MiB of BAR1 space. Verify Above 4G Decoding and Resizable BAR in firmware."
      fi
    fi
  else
    fail "nvidia-smi is not responding."
  fi

  if [[ -r /sys/module/nvidia_drm/parameters/modeset ]] \
    && [[ $(< /sys/module/nvidia_drm/parameters/modeset) == Y ]]; then
    pass "NVIDIA DRM modesetting is enabled."
  else
    fail "NVIDIA DRM modesetting is not enabled."
  fi

  # Video-memory preservation comes from the packaged NVIDIA configuration;
  # this repository deliberately adds no module parameter overrides.
  nvidia_params="$(cat /proc/driver/nvidia/params 2>/dev/null || true)"
  if grep -qE '^[[:space:]]*UseKernelSuspendNotifiers:[[:space:]]*1[[:space:]]*$' <<< "${nvidia_params}"; then
    pass "NVIDIA preserves video memory across sleep through kernel suspend notifiers."
  elif [[ -z ${nvidia_params} ]]; then
    warn "Could not read /proc/driver/nvidia/params; the NVIDIA module may not be loaded yet."
  else
    warn "NVreg_UseKernelSuspendNotifiers is not enabled. Arch sets it in /usr/lib/modprobe.d/nvidia-sleep.conf; check for a local override in /etc/modprobe.d."
  fi

fi

check_package libva-utils

log_step "Video pipeline"
# Browser video is upscaled by handing it to mpv, because RTX Video Super
# Resolution has no Linux counterpart. These are the parts module 52 resolves at
# install time and module 50 cannot deploy as static files.
mpv_config_dir="${HOME}/.config/mpv"
shader_link="${mpv_config_dir}/shaders"
required_shader=ArtCNN_C4F16.glsl
if [[ ! -L ${shader_link} ]]; then
  fail "${shader_link} is not a symlink to the shader pack. Run ./install.sh 52."
elif [[ ! -e ${shader_link}/${required_shader} ]]; then
  fail "${shader_link} does not resolve to a directory containing ${required_shader}, which mpv.conf applies to every source below 1440p. Run ./install.sh 52."
else
  pass "The mpv shader pack is linked at ${shader_link}."
fi

if [[ -f ${mpv_config_dir}/mpv.conf ]]; then
  # Pointed at a path that cannot exist so mpv reads its configuration and then
  # exits at once. Failing to open that path is expected, so only mpv's own
  # configuration errors are matched, not its exit status.
  mpv_check_output="$(mpv --vo=null --ao=null --force-window=no \
    "${TMPDIR:-/tmp}/workstation-mpv-probe-$$-does-not-exist" 2>&1 || true)"
  if ! grep -Eq 'Error parsing|option not found' <<< "${mpv_check_output}"; then
    pass "mpv parses its deployed configuration without errors."
  else
    fail "mpv rejects its deployed configuration: ${mpv_check_output//$'\n'/; }"
  fi
else
  fail "${mpv_config_dir}/mpv.conf is missing. Run ./install.sh 50."
fi

# The manifest is what lets the ff2mpv add-on start the host process. Zen reads
# Firefox's directory rather than one of its own, so this path is correct even
# though no Firefox is installed.
ff2mpv_manifest="${HOME}/.mozilla/native-messaging-hosts/ff2mpv.json"
if [[ ! -f ${ff2mpv_manifest} ]]; then
  fail "Missing ff2mpv native messaging manifest: ${ff2mpv_manifest}. Run ./install.sh 52."
elif ! command -v jq >/dev/null 2>&1; then
  warn "jq is unavailable, so ${ff2mpv_manifest} was not validated."
else
  ff2mpv_host="$(jq -er '.path' "${ff2mpv_manifest}" 2>/dev/null || true)"
  ff2mpv_allowed="$(jq -er '.allowed_extensions | index("ff2mpv@yossarian.net")' "${ff2mpv_manifest}" 2>/dev/null || true)"
  if [[ -n ${ff2mpv_host} && -x ${ff2mpv_host} && ${ff2mpv_allowed} != null && -n ${ff2mpv_allowed} ]]; then
    pass "The ff2mpv manifest authorises the add-on and points at ${ff2mpv_host}."
  else
    fail "${ff2mpv_manifest} does not name an executable host authorised for ff2mpv@yossarian.net. Run ./install.sh 52."
  fi
fi

# The add-on cannot be installed by this repository, so its absence is a warning
# rather than a failure: everything else here still works from the command line.
zen_root=''
for candidate in "${XDG_CONFIG_HOME:-${HOME}/.config}/zen" "${HOME}/.zen"; do
  if [[ -r ${candidate}/profiles.ini ]]; then
    zen_root=${candidate}
    break
  fi
done
if [[ -n ${zen_root} && -d ${zen_root} ]] \
  && ! find "${zen_root}" -maxdepth 3 -name 'ff2mpv@yossarian.net*' -print -quit 2>/dev/null | grep -q .; then
  warn "The ff2mpv add-on does not appear to be installed in Zen. Get it from https://addons.mozilla.org/firefox/addon/ff2mpv/ ; the native host is ready for it."
fi

log_step "Browser hardware decoding"
# hypr-user.lua sets these through hl.env, so a check.sh run from a terminal
# inside the session sees exactly what a browser launched from the session sees.
if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
  for variable in LIBVA_DRIVER_NAME:nvidia NVD_BACKEND:direct MOZ_DISABLE_RDD_SANDBOX:1; do
    variable_name=${variable%%:*}
    variable_expected=${variable#*:}
    if [[ ${!variable_name:-} == "${variable_expected}" ]]; then
      pass "${variable_name} is ${variable_expected} in the session environment."
    else
      fail "${variable_name} is '${!variable_name:-unset}', not '${variable_expected}'. Run ./install.sh 50, then log out and back in."
    fi
  done
  # vainfo is only meaningful with those variables present, since libva will not
  # otherwise load a driver at all. Outside the session it would report a
  # failure that says nothing about how the browsers are configured.
  if command -v vainfo >/dev/null 2>&1; then
    vainfo_output="$(vainfo 2>&1 || true)"
    if grep -qE 'VAProfileH264|VAProfileVP9|VAProfileAV1' <<< "${vainfo_output}"; then
      pass "VA-API reports hardware decode profiles."
    else
      fail "VA-API exposes no decode profiles, so both browsers will decode video on the CPU: ${vainfo_output//$'\n'/; }"
    fi
  fi
else
  warn "Not running inside a Hyprland session, so the browser decoding environment was not checked."
fi

# Zen needs the preference as well as the environment: Firefox has shipped
# VA-API on by default since 137 but still declines to use it on NVIDIA unless
# it is forced.
if [[ -z ${zen_root} ]]; then
  warn "No Zen profile root exists yet; start Zen once, then run ./install.sh 52."
else
  zen_profiles_ini="${zen_root}/profiles.ini"
  mapfile -t checked_zen_profiles < <(awk -v root="${zen_root}" '
    function flush() {
      if (path != "") { print (relative == "0" ? path : root "/" path) }
      path = ""; relative = "1"
    }
    { sub(/\r$/, "") }
    /^\[/ { flush(); next }
    /^[[:space:]]*Path[[:space:]]*=/ { sub(/^[^=]*=/, ""); path = $0; next }
    /^[[:space:]]*IsRelative[[:space:]]*=/ { sub(/^[^=]*=/, ""); relative = $0; next }
    END { flush() }
  ' "${zen_profiles_ini}")

  zen_prefs_ok=true
  zen_profiles_seen=0
  for zen_profile in "${checked_zen_profiles[@]}"; do
    [[ -d ${zen_profile} ]] || continue
    zen_profiles_seen=$((zen_profiles_seen + 1))
    if ! grep -Fq 'user_pref("media.hardware-video-decoding.force-enabled", true);' "${zen_profile}/user.js" 2>/dev/null; then
      fail "Zen profile does not force hardware video decoding: ${zen_profile}/user.js. Run ./install.sh 52."
      zen_prefs_ok=false
    fi
  done
  if [[ ${zen_profiles_seen} -eq 0 ]]; then
    warn "${zen_profiles_ini} lists no existing profile directory."
  elif [[ ${zen_prefs_ok} == true ]]; then
    pass "All ${zen_profiles_seen} Zen profile(s) force hardware video decoding."
  fi
fi

# Helium reads its flags from the file module 50 deploys. The dotfile comparison
# above already catches drift; this catches the wrapper not reading it at all,
# which is what happens if the AUR package is replaced by a plain upstream build.
helium_flags="${HOME}/.config/helium-browser-flags.conf"
if ! command -v helium-browser >/dev/null 2>&1; then
  fail "helium-browser is not installed. Run ./install.sh 25."
elif [[ ! -f ${helium_flags} ]]; then
  fail "Missing Helium flags file: ${helium_flags}. Run ./install.sh 50."
elif grep -qF -- '--enable-features=AcceleratedVideoDecodeLinuxGL,VaapiOnNvidiaGPUs' "${helium_flags}"; then
  pass "Helium is configured for VA-API decoding; confirm it took effect at helium://gpu."
else
  fail "${helium_flags} does not enable VA-API decoding. Run ./install.sh 50."
fi

log_step "Desktop integration"
# Caelestia's execs.lua names this agent by absolute path. If it is missing,
# nothing authenticates GUI privilege prompts and the failure is silent.
if [[ -x /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 ]]; then
  pass "The polkit authentication agent Caelestia starts is installed."
else
  fail "/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 is missing, so no polkit agent runs. Run ./install.sh 10."
fi

if grep -Eq '^[[:space:]]*session[[:space:]]+optional[[:space:]]+pam_gnome_keyring\.so[[:space:]]+auto_start' /etc/pam.d/greetd 2>/dev/null; then
  pass "greetd unlocks the login keyring through PAM."
else
  fail "/etc/pam.d/greetd does not unlock the login keyring, so secrets prompt every session. Run ./install.sh 40."
fi

if default_browser="$(xdg-settings get default-web-browser 2>/dev/null)" && [[ ${default_browser} == *helium* ]]; then
  pass "The default browser for xdg-open is ${default_browser}."
else
  fail "The default browser is '${default_browser:-unset}', not a Helium desktop entry. Run ./install.sh 50."
fi

for pacman_option in Color VerbosePkgLists ParallelDownloads; do
  if grep -Eq "^${pacman_option}\\b" /etc/pacman.conf 2>/dev/null; then
    pass "pacman option enabled: ${pacman_option}"
  else
    warn "pacman option not enabled: ${pacman_option}. Run ./install.sh 00."
  fi
done

log_step "Snapshots"
root_fstype="$(findmnt --noheadings --output FSTYPE --target / 2>/dev/null || true)"
if [[ ${root_fstype} == btrfs ]]; then
  if sudo -n snapper -c root get-config >/dev/null 2>&1; then
    pass "A snapper 'root' configuration exists, so snap-pac brackets pacman transactions."
  else
    warn "Could not confirm the snapper 'root' configuration (this check does not prompt for sudo). Verify with: sudo snapper -c root get-config"
  fi
  for service in snapper-timeline.timer snapper-cleanup.timer; do
    check_enabled "${service}"
  done
else
  warn "The root filesystem is ${root_fstype:-unknown}, not btrfs; this repository only adds pre-upgrade snapshots on btrfs."
fi

log_step "Boot menu"
limine_configs=()
boot_reader=()
if sudo -n true >/dev/null 2>&1; then
  boot_reader=(sudo -n)
fi
# Module 55 themes every candidate it finds, because which one Limine reads
# depends on how the firmware reports the volume it booted from. Check them
# all for the same reason.
for candidate in \
  /boot/limine/limine.conf /boot/limine.conf \
  /boot/EFI/limine/limine.conf /boot/EFI/arch-limine/limine.conf /boot/EFI/BOOT/limine.conf \
  /boot/efi/limine/limine.conf /boot/efi/limine.conf \
  /boot/efi/EFI/limine/limine.conf /boot/efi/EFI/arch-limine/limine.conf /boot/efi/EFI/BOOT/limine.conf \
  /efi/limine/limine.conf /efi/limine.conf \
  /efi/EFI/limine/limine.conf /efi/EFI/arch-limine/limine.conf /efi/EFI/BOOT/limine.conf; do
  if "${boot_reader[@]}" test -f "${candidate}" 2>/dev/null; then
    limine_configs+=("${candidate}")
  fi
done
if ((${#limine_configs[@]} == 0)); then
  warn "No readable limine.conf found. If /boot is root-only, rerun this check while the sudo credential is cached."
else
  for limine_config in "${limine_configs[@]}"; do
    if "${boot_reader[@]}" grep -Fq '# >>> workstation appearance >>>' "${limine_config}"; then
      pass "The Limine appearance block is applied in ${limine_config}."
    else
      fail "${limine_config} carries no workstation appearance block. Run ./install.sh 55."
    fi
    if "${boot_reader[@]}" grep -Eq '^term_palette:[[:space:]]' "${limine_config}" \
      && ! "${boot_reader[@]}" grep -Eq '^wallpaper:[[:space:]]' "${limine_config}"; then
      pass "${limine_config} uses the configured wallpaper-free terminal palette."
    else
      fail "Limine's wallpaper-free terminal palette is not active in ${limine_config}. Run ./install.sh 55."
    fi
  done
fi

# archinstall labels its own entry "Arch Linux Limine Bootloader", and module
# 55 keeps that one rather than stacking a second entry beside it, so accept
# any entry whose label names Limine or whose loader path is Limine's. The
# label is taken from before the device path, which contains "limine" itself
# whenever Limine is installed under one of its own directories.
if efibootmgr -v 2>/dev/null | awk '
    /^Boot[[:xdigit:]][[:xdigit:]][[:xdigit:]][[:xdigit:]][*]?[[:space:]]/ {
      line = $0
      sub(/^Boot[[:xdigit:]]{4}[*]?[[:space:]]+/, "", line)
      label = line
      sub(/\t.*$/, "", label)
      sub(/(HD|PciRoot|VenHw|FvVol)\(.*$/, "", label)
      # Older efibootmgr wrapped the file path as File(\EFI\...); current
      # releases print it bare after the device node, as )/\EFI\...
      path = ""
      if (match(line, /[Ff]ile\([^)]*\)/)) {
        path = substr(line, RSTART + 5, RLENGTH - 6)
      } else if (match(line, /\)\/\\[^ \t]*/)) {
        path = substr(line, RSTART + 2, RLENGTH - 2)
      }
      if (tolower(label) ~ /limine/ || tolower(path) ~ /limine/) { found = 1 }
    }
    END { exit(found ? 0 : 1) }
  '; then
  pass "A Limine firmware entry exists."
else
  fail "No Limine firmware entry exists. Run ./install.sh 55."
fi

printf '\nResult: %d error(s), %d warning(s).\n' "${failures}" "${warnings}"
[[ ${failures} -eq 0 ]]
