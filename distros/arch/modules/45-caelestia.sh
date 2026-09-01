#!/usr/bin/env bash
set -Eeuo pipefail

readonly DISTRO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT="$(cd -- "${DISTRO_ROOT}/../.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"
# Modules run in their own bash process, so the menu functions sourced by
# install.sh are not inherited; source them here (guarded by menu.sh itself).
# shellcheck source=lib/menu.sh
source "${REPO_ROOT}/lib/menu.sh"

require_command caelestia
require_command paru
require_command pacman
require_command jq
require_command git
require_command Hyprland
require_command vercmp
require_command patch

readonly CAELESTIA_STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/caelestia"
readonly CAELESTIA_STATE_FILE="${CAELESTIA_STATE_DIR}/dots-state.json"
readonly CAELESTIA_DOTS_DIR="${CAELESTIA_STATE_DIR}/dots"
readonly CAELESTIA_EXECS_PATCH="${DISTRO_ROOT}/etc/caelestia/execs-night-light.patch"
readonly HYPR_CONFIG_DIR="${HOME}/.config/hypr"
readonly FISH_CONFIG="${HOME}/.config/fish/config.fish"
readonly WALLPAPER_REPOSITORY='https://github.com/dharmx/walls.git'
readonly WALLPAPER_DIR="${HOME}/Pictures/Wallpapers"

# The categories you actually keep. Only these are downloaded. The rest of
# the upstream repository is never fetched, so the checkout stays small.
readonly -a WALLPAPER_KEPT_CATEGORIES=(
  abstract animated anime apeiros calm centered chillop devicons digital
  dreamcore evangelion gruvbox m-26.jp minimal mountain nature nord outrun
  painting pixel radium spam stalenhag tile unsorted
)

# A private or missing repository must fail loudly instead of sitting at a
# credential prompt in the middle of the setup. GIT_TERMINAL_PROMPT only
# disables terminal prompts: an askpass helper (SSH_ASKPASS or a desktop
# agent picked up through GIT_ASKPASS) would still ask, so point that at
# /bin/true as well; git then gets an empty username and aborts.
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=/bin/true
# Caelestia ships no per-terminal colour files. Its shell writes the active
# scheme to this file as escape sequences, and its fish config replays them at
# every interactive start, which is what themes the terminal.
readonly CAELESTIA_SEQUENCES_PATTERN='caelestia/sequences.txt'

readonly UWSM_CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/uwsm"
readonly CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
readonly STATE_HOME="${XDG_STATE_HOME:-${HOME}/.local/state}"
readonly SPOTIFY_PREFS_FILE="${CONFIG_HOME}/spotify/prefs"
readonly SPICETIFY_THEME_DIR="${CONFIG_HOME}/spicetify/Themes/caelestia"
readonly SPICETIFY_BACKUP_DIR="${STATE_HOME}/spicetify/Backup"

readonly HYPR_MAIN_CONFIG="${HYPR_CONFIG_DIR}/hyprland.lua"
readonly HYPR_EXECS_CONFIG="${HYPR_CONFIG_DIR}/hyprland/execs.lua"
readonly HYPR_EXECS_REQUIRE_PATTERN="require[[:space:]]*\\([[:space:]]*['\"]hyprland\\.execs['\"][[:space:]]*\\)"
readonly HYPR_START_EVENT_PATTERN="hl\\.on[[:space:]]*\\([[:space:]]*['\"]hyprland\\.start['\"]"
readonly CAELESTIA_AUTOSTART_PATTERN="hl\\.exec_cmd[[:space:]]*\\([[:space:]]*['\"]caelestia[[:space:]]+shell[[:space:]]+-d['\"][[:space:]]*\\)"

[[ -r ${CAELESTIA_EXECS_PATCH} ]] || die "Missing Caelestia override: ${CAELESTIA_EXECS_PATCH}"

render_expected_hypr_file() {
  local source_file=$1 relative_file=$2 output_file=$3

  cp -- "${source_file}" "${output_file}"
  if [[ ${relative_file} == hyprland/execs.lua ]]; then
    patch --silent --fuzz=0 --no-backup-if-mismatch "${output_file}" "${CAELESTIA_EXECS_PATCH}" \
      || die "Caelestia changed hyprland/execs.lua; refresh ${CAELESTIA_EXECS_PATCH} before deploying it."
  fi
}

deployed_hypr_file_matches() {
  local source_file=$1 relative_file=$2 target_file=$3 expected_file

  if [[ ${relative_file} != hyprland/execs.lua ]]; then
    cmp -s -- "${source_file}" "${target_file}"
    return
  fi

  expected_file="$(mktemp "${TMPDIR:-/tmp}/workstation-caelestia-expected-XXXXXX")"
  render_expected_hypr_file "${source_file}" "${relative_file}" "${expected_file}"
  local status=0
  cmp -s -- "${expected_file}" "${target_file}" || status=$?
  rm -f -- "${expected_file}"
  return "${status}"
}

apply_caelestia_overrides() {
  local source_file="${CAELESTIA_DOTS_DIR}/hypr/hyprland/execs.lua"
  local target_file="${HYPR_EXECS_CONFIG}" expected_file

  [[ -f ${source_file} && -f ${target_file} ]] || return 1
  expected_file="$(mktemp "${TMPDIR:-/tmp}/workstation-caelestia-execs-XXXXXX")"
  render_expected_hypr_file "${source_file}" hyprland/execs.lua "${expected_file}"

  if cmp -s -- "${expected_file}" "${target_file}"; then
    rm -f -- "${expected_file}"
    return 0
  fi
  if ! cmp -s -- "${source_file}" "${target_file}"; then
    rm -f -- "${expected_file}"
    return 1
  fi

  install --mode=0644 "${expected_file}" "${target_file}"
  rm -f -- "${expected_file}"
  log_success "Made Caelestia's automatic night light controllable through hypr-vars.lua."
}

hyprland_version="$(pacman -Q hyprland 2>/dev/null | awk 'NF >= 2 { print $2; exit }')" || hyprland_version=''
if [[ -z ${hyprland_version} || $(vercmp "${hyprland_version}" 0.55.0) -lt 0 ]]; then
  die "Caelestia's native Lua config requires Hyprland 0.55 or newer; installed version: ${hyprland_version:-missing}. Run ./install.sh 00 and ./install.sh 10 first."
fi

caelestia_deployed_tree_complete() {
  local applied_rev relative_file source_file source_rev target_file
  local found_file=false

  [[ -d ${CAELESTIA_DOTS_DIR}/.git ]] || return 1
  applied_rev="$(jq -er '.applied_rev | select(type == "string" and length > 0)' "${CAELESTIA_STATE_FILE}" 2>/dev/null)" \
    || return 1
  source_rev="$(git -C "${CAELESTIA_DOTS_DIR}" rev-parse HEAD 2>/dev/null)" || return 1
  [[ ${source_rev} == "${applied_rev}" && -d ${CAELESTIA_DOTS_DIR}/hypr ]] || return 1

  if find "${CAELESTIA_DOTS_DIR}/hypr" -mindepth 1 ! -type d ! -type f -print -quit | grep -q .; then
    return 1
  fi

  while IFS= read -r -d '' source_file; do
    found_file=true
    relative_file="${source_file#"${CAELESTIA_DOTS_DIR}"/hypr/}"
    target_file="${HYPR_CONFIG_DIR}/${relative_file}"
    [[ -f ${target_file} ]] || return 1
    ! path_has_symlink "${target_file}" || return 1
    deployed_hypr_file_matches "${source_file}" "${relative_file}" "${target_file}" || return 1
  done < <(find "${CAELESTIA_DOTS_DIR}/hypr" -type f -print0)

  [[ ${found_file} == true ]]
}

caelestia_component_enabled() {
  local component=$1
  jq -e --arg component "${component}" \
    '.enabled_components | type == "array" and index($component) != null' \
    "${CAELESTIA_STATE_FILE}" >/dev/null 2>&1
}

caelestia_integration_selected() {
  local component=$1
  caelestia_component_enabled "${component}" && return 0
  case ${component} in
    vscode)
      caelestia_package_selected apps code
      ;;
    vscodium)
      caelestia_package_selected aur vscodium-bin
      ;;
    discord)
      caelestia_package_selected aur equibop-bin
      ;;
    spotify)
      caelestia_package_selected aur spotify \
        && caelestia_package_selected aur spicetify-cli
      ;;
    *)
      return 1
      ;;
  esac
}

# Keep the app integrations tied to the package choices made earlier in this
# one-shot setup. Caelestia's component prompt is separate from our package
# picker, so these components start enabled when their corresponding app was
# selected. The user can still turn one off in the Caelestia menu.
caelestia_package_selected() {
  local manifest=$1 package=$2
  ! selection_is_skipped "${manifest}" "${package}" \
    && pacman -Q "${package}" >/dev/null 2>&1
}

caelestia_component_is_app_default() {
  local component=$1
  case ${component} in
    spotify)
      caelestia_package_selected aur spotify \
        && caelestia_package_selected aur spicetify-cli
      ;;
    vscode)
      caelestia_package_selected apps code
      ;;
    discord)
      caelestia_package_selected aur equibop-bin
      ;;
    *)
      return 1
      ;;
  esac
}

json_update_object() {
  local file=$1 filter=$2 input tmp
  if path_has_symlink "${file}" || path_has_symlink "$(dirname -- "${file}")"; then
    die "Refusing to update JSON through a symlink: ${file}"
  fi
  install -d "$(dirname -- "${file}")"
  tmp="$(mktemp "${TMPDIR:-/tmp}/workstation-caelestia-json-XXXXXX")"

  if [[ -f ${file} ]]; then
    input=${file}
    jq -e 'type == "object"' "${input}" >/dev/null \
      || die "Cannot update ${file}: it is not a JSON object."
  else
    input="$(mktemp "${TMPDIR:-/tmp}/workstation-caelestia-json-input-XXXXXX")"
    printf '{}\n' > "${input}"
  fi

  if ! jq "${filter}" "${input}" > "${tmp}"; then
    [[ ${input} == "${file}" ]] || rm -f -- "${input}"
    rm -f -- "${tmp}"
    die "Unable to update ${file}."
  fi
  install --mode=0644 "${tmp}" "${file}"
  rm -f -- "${tmp}"
  [[ ${input} == "${file}" ]] || rm -f -- "${input}"
}

activate_editor_theme() {
  local editor=$1 settings_file
  case ${editor} in
    vscode) settings_file="${CONFIG_HOME}/Code/User/settings.json" ;;
    vscodium) settings_file="${CONFIG_HOME}/VSCodium/User/settings.json" ;;
    *) die "Unknown Caelestia editor component: ${editor}" ;;
  esac

  json_update_object "${settings_file}" '."workbench.colorTheme" = "Caelestia"'
  log_success "${editor}: Caelestia is now the active colour theme."
}

activate_equibop_theme() {
  local settings_file="${CONFIG_HOME}/equibop/settings/settings.json"
  local theme_file="${CONFIG_HOME}/equibop/themes/caelestia.theme.css"

  [[ -f ${theme_file} ]] \
    || die "Caelestia did not generate the Equibop theme at ${theme_file}."
  json_update_object "${settings_file}" \
    '.enabledThemes = ((if (.enabledThemes | type) == "array" then .enabledThemes else [] end) | if index("caelestia.theme.css") == null then . + ["caelestia.theme.css"] else . end)'
  log_success 'Equibop: the Caelestia theme is enabled in its local theme list.'
}

# Spotify's own directory: the one holding the Apps folder Spicetify rewrites.
# The package file list is authoritative; the literal paths only cover a
# Spotify installed outside pacman.
spotify_install_dir() {
  local candidate
  local -a candidates=()

  candidate="$(pacman -Ql spotify 2>/dev/null \
    | awk '$2 ~ /\/Apps\/$/ { print substr($2, 1, length($2) - 6); exit }')" \
    || candidate=''
  [[ -n ${candidate} ]] && candidates+=("${candidate}")
  candidates+=(/opt/spotify /opt/spotify/spotify-client /usr/share/spotify)

  for candidate in "${candidates[@]}"; do
    if [[ -d ${candidate}/Apps ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  return 1
}

# Spicetify only accepts a prefs path that already exists, and Spotify writes
# that file the first time it starts. A machine set up in one pass has never
# started Spotify, so Spicetify's auto-detection finds nothing and aborts with
# "Cannot detect Spotify \"prefs\" file location". Create the empty file Spotify
# would have created; Spotify fills in its own settings on first launch.
ensure_spotify_prefs() {
  local prefs_dir
  prefs_dir="$(dirname -- "${SPOTIFY_PREFS_FILE}")"
  if [[ -f ${SPOTIFY_PREFS_FILE} ]]; then
    return 0
  fi
  if path_has_symlink "${prefs_dir}"; then
    die "Refusing to create Spotify's prefs file through a symlink: ${prefs_dir}"
  fi
  install -d "${prefs_dir}"
  : > "${SPOTIFY_PREFS_FILE}"
  chmod 0600 "${SPOTIFY_PREFS_FILE}"
  log_info "Created an empty ${SPOTIFY_PREFS_FILE}; Spotify fills it in on first launch."
}

# Applying a theme deletes and rebuilds Spotify's Apps directory, so the
# desktop user needs write access to it and to the root-owned directory that
# holds it. Upstream tells Arch users to make both world-writable; give them
# to this user instead, which fixes the same failure without opening a
# root-owned tree to every local account. A spotify package upgrade resets the
# ownership, and rerunning this module restores it.
grant_spotify_write_access() {
  local install_dir=$1 owner
  owner="$(id -u):$(id -g)"
  as_root chown -h "${owner}" -- "${install_dir}" \
    || die "Could not take ownership of ${install_dir} for Spicetify."
  as_root chown -Rh "${owner}" -- "${install_dir}/Apps" \
    || die "Could not take ownership of ${install_dir}/Apps for Spicetify."
  as_root chmod u+rwX -- "${install_dir}"
  as_root chmod -R u+rwX -- "${install_dir}/Apps"
}

# Spotify still carries the packaged .spa archives, so Spicetify can take (or
# retake) its backup from them. This mirrors Spicetify's own "backupable" test.
spotify_is_backupable() {
  compgen -G "$1/Apps/*.spa" > /dev/null 2>&1
}

spicetify_has_backup() {
  compgen -G "${SPICETIFY_BACKUP_DIR}/*.spa" > /dev/null 2>&1
}

# Spicetify has already replaced the stock archive with an unpacked, themed
# xpui directory, and its configuration still names the Caelestia theme.
spicetify_theme_active() {
  local install_dir=$1
  [[ -d ${install_dir}/Apps/xpui && -f ${install_dir}/Apps/xpui/user.css ]] || return 1
  spicetify config current_theme 2>/dev/null \
    | grep -Eq '(^|[[:space:]=])caelestia([[:space:]]|$)'
}

activate_spicetify_theme() {
  local install_dir
  require_command spicetify

  log_step 'Activating the Caelestia Spicetify theme'
  install_dir="$(spotify_install_dir)" \
    || die 'Could not find the Spotify installation directory. Reinstall the spotify package, then rerun ./install.sh 45.'
  [[ -d ${SPICETIFY_THEME_DIR} ]] \
    || die "Caelestia's Spicetify theme is missing at ${SPICETIFY_THEME_DIR}; rerun the Caelestia installer with its spotify component enabled."

  if spicetify_theme_active "${install_dir}"; then
    log_success 'Spotify: Spicetify is already using Caelestia.'
    return 0
  fi

  ensure_spotify_prefs
  grant_spotify_write_access "${install_dir}"

  # Pin both paths instead of leaving them to auto-detection, which reads a
  # prefs file Spotify has not written yet and a `whereis spotify` result that
  # depends on the launcher being on PATH.
  spicetify config \
    spotify_path "${install_dir}" \
    prefs_path "${SPOTIFY_PREFS_FILE}" \
    current_theme caelestia \
    color_scheme caelestia \
    custom_apps marketplace \
    || die 'Spicetify rejected the Caelestia theme configuration.'

  # `spicetify apply` refuses to run without a backup of the stock client, and
  # refuses again when the backup it has was taken from a different Spotify
  # version, so neither state can be assumed. Take the branch that ends with a
  # backup matching the installed client. -n keeps Spicetify from launching
  # Spotify afterwards: this still runs inside the installer, usually with no
  # desktop session to launch it into.
  if spotify_is_backupable "${install_dir}"; then
    spicetify -n backup apply \
      || die 'Spicetify could not back up and theme Spotify.'
  elif spicetify_has_backup; then
    spicetify -n restore backup apply \
      || die 'Spicetify could not restore, back up, and theme Spotify.'
  else
    die "Spotify at ${install_dir} is already modified and Spicetify has no backup to restore. Reinstall the spotify package, then rerun ./install.sh 45."
  fi
  log_success 'Spotify: Spicetify is using Caelestia.'
}

activate_caelestia_integration() {
  case $1 in
    vscode | vscodium) activate_editor_theme "$1" ;;
    discord) activate_equibop_theme ;;
    spotify) activate_spicetify_theme ;;
    *) die "Unknown Caelestia integration: $1" ;;
  esac
}

# The app integrations are independent of one another, so each one runs in its
# own subshell: a failing integration still reports its cause, but it no longer
# swallows the ones queued behind it. The whole step still fails afterwards, so
# nothing silently ships half-themed.
activate_caelestia_integrations() {
  local integration
  local -a failed=()

  for integration in vscode vscodium discord spotify; do
    caelestia_integration_selected "${integration}" || continue
    ( activate_caelestia_integration "${integration}" ) || failed+=("${integration}")
  done

  ((${#failed[@]} == 0)) \
    || die "Could not activate the Caelestia theme for: ${failed[*]}. Fix the cause reported above, then rerun ./install.sh 45."
}

caelestia_config_complete() {
  command -v qs >/dev/null 2>&1 || return 1
  pacman -Q caelestia-shell >/dev/null 2>&1 || return 1

  [[ -f ${CAELESTIA_STATE_FILE} ]] || return 1
  jq -e '
    (.applied_rev | type == "string" and length > 0)
    and (.enabled_components | type == "array" and index("hypr") != null)
    and (.enabled_components | index("fish") != null)
    and (.enabled_components | index("uwsm") != null)
  ' "${CAELESTIA_STATE_FILE}" >/dev/null 2>&1 || return 1

  # Without the fish component nothing replays the scheme, so every terminal
  # keeps its own default palette.
  [[ -f ${FISH_CONFIG} ]] || return 1
  grep -Fq "${CAELESTIA_SEQUENCES_PATTERN}" "${FISH_CONFIG}" || return 1

  caelestia_deployed_tree_complete || return 1
  ! find "${HYPR_CONFIG_DIR}" -type l -print -quit | grep -q . || return 1

  grep -Eq "${HYPR_EXECS_REQUIRE_PATTERN}" "${HYPR_MAIN_CONFIG}" || return 1
  grep -Eq "${HYPR_START_EVENT_PATTERN}" "${HYPR_EXECS_CONFIG}" || return 1
  grep -Eq "${CAELESTIA_AUTOSTART_PATTERN}" "${HYPR_EXECS_CONFIG}" || return 1

  # The uwsm component deploys the environment files the uwsm-managed session
  # sources. Without them the session entry still appears in the greeter but
  # starts without Caelestia's environment, so treat it as incomplete.
  [[ -f ${UWSM_CONFIG_DIR}/env ]] || return 1
  [[ -f ${UWSM_CONFIG_DIR}/env-hyprland ]] || return 1

  Hyprland --verify-config --config "${HYPR_MAIN_CONFIG}" >/dev/null 2>&1
}

# The optional (off-by-default) component names Caelestia would offer in its
# own prompt, parsed from the installer's help output. The list is coloured
# and tab-aligned, so strip ANSI codes and take the name before the marker;
# only "(off)" rows are optional, "(default)" ones are always enabled anyway.
caelestia_optional_components() {
  local help_text line name

  help_text="$(caelestia install --help 2>&1)" || return 1
  while IFS= read -r line; do
    line="$(printf '%s' "${line}" | sed -e 's/\x1b\[[0-9;]*m//g')"
    [[ ${line} == *'(off)' ]] || continue
    name="${line%%$'\t'*}"
    name="${name//[[:space:]]/}"
    if [[ -n ${name} ]]; then
      printf '%s\n' "${name}"
    fi
  done <<< "${help_text}"
  return 0
}

# Ask which optional components (uwsm, spotify, vscodium, ...) to install.
# Caelestia only shows this prompt when NO component flag is passed, and the
# flags are mandatory here to keep firefox off, so the selection is gathered
# with the local menu instead and handed to the installer explicitly.
choose_caelestia_components() {
  local -a optional=() rows=() checked=() required=()
  local index name width=0 rc=0

  mapfile -t optional < <(caelestia_optional_components)
  ((${#optional[@]} > 0)) \
    || die "Could not read Caelestia's optional component list from 'caelestia install --help'; refusing to run the installer without asking."

  for name in "${optional[@]}"; do
    if ((${#name} > width)); then
      width=${#name}
    fi
  done
  for index in "${!optional[@]}"; do
    name="${optional[index]}"
    rows+=("$(printf '%-*s' "${width}" "${name}")")
    checked+=(0)
    required+=(0)
    if [[ ${name} == uwsm ]]; then
      rows[index]+='   - required for the uwsm-managed Hyprland session'
      checked[index]=1
      required[index]=1
    elif caelestia_component_is_app_default "${name}"; then
      rows[index]+='   - enabled because its app package is selected'
      checked[index]=1
    fi
  done

  menu_select_many \
    '[*]  Caelestia: pick the optional components to install' \
    'space toggle - a all/none - r reset - enter apply' \
    checked required "${rows[@]}" < /dev/tty || rc=$?
  if ((rc != 0)); then
    die 'Component selection cancelled.'
  fi

  CAELESTIA_ENABLED_COMPONENTS=()
  for index in "${!optional[@]}"; do
    if ((checked[index])); then
      CAELESTIA_ENABLED_COMPONENTS+=("${optional[index]}")
    fi
  done
  return 0
}

wallpaper_repository_matches() {
  local origin_url

  origin_url="$(git -C "${WALLPAPER_DIR}" remote get-url origin 2>/dev/null)" || return 1
  [[ ${origin_url%.git} == ${WALLPAPER_REPOSITORY%.git} ]]
}

apply_wallpaper_selection() {
  ((${#WALLPAPER_KEPT_CATEGORIES[@]} > 0)) \
    || die 'The wallpaper keep list is empty; nothing to select.'
  git -C "${WALLPAPER_DIR}" sparse-checkout set "${WALLPAPER_KEPT_CATEGORIES[@]}"
}

install_wallpaper_repository() {
  if [[ -d ${WALLPAPER_DIR}/.git ]]; then
    if wallpaper_repository_matches; then
      git -C "${WALLPAPER_DIR}" pull --ff-only
      apply_wallpaper_selection
      log_success "Wallpapers updated at ${WALLPAPER_DIR}."
    else
      log_warn "${WALLPAPER_DIR} is a different repository; leaving it untouched."
    fi
  elif [[ -e ${WALLPAPER_DIR} || -L ${WALLPAPER_DIR} ]]; then
    log_warn "${WALLPAPER_DIR} already exists and is not a Git checkout; leaving it untouched."
  else
    if path_has_symlink "${HOME}/Pictures"; then
      die "Refusing to clone wallpapers through a symlinked directory: ${HOME}/Pictures"
    fi

    log_step "Cloning wallpapers for Caelestia"
    install -d "${HOME}/Pictures"
    git clone --depth 1 --filter=blob:none --sparse \
      "${WALLPAPER_REPOSITORY}" "${WALLPAPER_DIR}"
    apply_wallpaper_selection
    log_success "Wallpapers cloned to ${WALLPAPER_DIR}."
  fi
}

# Apply the local startup guard before unrelated wallpaper validation so an
# existing user-managed Wallpapers directory cannot re-enable night light.
apply_caelestia_overrides || true
install_wallpaper_repository

if caelestia_config_complete; then
  activate_caelestia_integrations
  log_success "The complete Caelestia configuration matches its applied revision plus managed overrides and passes Hyprland's verifier."
  exit 0
fi

# Quickshell is pulled in as a normal dependency of caelestia-shell by the
# Caelestia installer; on Arch nothing else provides or overrides it.

# The Caelestia installer reads its prompts from stdin and aborts silently on
# end of input (for example when the installation was started through
# `curl | bash`). Attach it to the terminal explicitly.
{ : < /dev/tty; } 2>/dev/null || die "The Caelestia installer is interactive and needs a terminal. Run ./install.sh 45 from a terminal session."

log_step "Running the Caelestia dotfiles installer"
log_warn "This step is interactive: answer the prompts. Building Quickshell takes a while."
# Passing any component flag makes the installer skip its component prompt and
# take the manifest defaults instead, so the component set stops depending on
# how the prompt was answered. That matters because the deployed Hyprland
# config executes what those components install (gnome-keyring, polkit-gnome,
# trash-cli, the GTK and Qt theming) and hl.exec_cmd failures are silent.
#
# The flag form has a cost: Caelestia only offers its OPTIONAL components
# (uwsm, spotify, vscodium, ...) when no component flag is given, so a bare
# --disable-components firefox silently drops the whole selection step and
# leaves the machine without a uwsm-managed Hyprland session. The optional
# set is therefore picked in the local menu (uwsm pinned as required) and
# passed explicitly. firefox stays the one default turned off: this system
# uses Brave Origin.
#
# Older caelestia-cli releases have no component flags at all, so fall back
# to the fully interactive form rather than dying on an argument error.
if caelestia install --help 2>&1 | grep -Fq -- '--disable-components'; then
  choose_caelestia_components
  caelestia_installer_args=(install --disable-components firefox)
  if ((${#CAELESTIA_ENABLED_COMPONENTS[@]} > 0)); then
    caelestia_installer_args+=(
      --enable-components "$(IFS=,; echo "${CAELESTIA_ENABLED_COMPONENTS[*]}")"
    )
  fi
  caelestia "${caelestia_installer_args[@]}" < /dev/tty
else
  log_warn "This caelestia-cli has no component flags; the installer will ask instead."
  log_warn "Enable at least 'uwsm' alongside anything else you want: the greeter starts the uwsm-managed Hyprland session, and skipping it leaves no working session."
  caelestia install < /dev/tty
fi

apply_caelestia_overrides \
  || die "Unable to apply the managed Caelestia night-light override after installation."

activate_caelestia_integrations

if ! caelestia_config_complete; then
  if [[ -f ${HYPR_MAIN_CONFIG} ]]; then
    verify_output="$(Hyprland --verify-config --config "${HYPR_MAIN_CONFIG}" 2>&1)" || true
    [[ -z ${verify_output} ]] || log_error "Hyprland config verification output: ${verify_output//$'\n'/; }"
  fi
  die "The Caelestia installer exited without a complete managed copy of its Hyprland tree, its fish and uwsm components, required packages, valid saved state, or a Hyprland-verifiable shell startup callback. Review the installer and verification output."
fi

log_success "Caelestia's complete Hyprland tree matches the applied upstream revision plus managed overrides and passes Hyprland's config verifier."
