#!/usr/bin/env bash
set -Eeuo pipefail

readonly DISTRO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT="$(cd -- "${DISTRO_ROOT}/../.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"

# Everything module 50 could not deploy as a static file, because it depends on
# a path only this machine knows: where pacman put the shader pack, where the
# ff2mpv host binary landed, and which Zen profiles exist.

readonly MPV_CONFIG_DIR="${HOME}/.config/mpv"
readonly SHADER_LINK="${MPV_CONFIG_DIR}/shaders"
readonly ZEN_CONFIG_ROOT="${XDG_CONFIG_HOME:-${HOME}/.config}/zen"
readonly ZEN_LEGACY_ROOT="${HOME}/.zen"
readonly NATIVE_HOST_DIR="${HOME}/.mozilla/native-messaging-hosts"
readonly PREF_BEGIN='// >>> workstation video decoding >>>'
readonly PREF_END='// <<< workstation video decoding <<<'

require_command mpv
require_command pacman

# mpv.conf applies this one through a conditional auto profile, so a rename in
# the package would silently disable the upscaler on every file below 1440p.
readonly REQUIRED_SHADER=ArtCNN_C4F16.glsl
# input.conf binds these. A missing one breaks a keybinding, not playback.
readonly -a OPTIONAL_SHADERS=(
  ArtCNN_C4F32.glsl
  FSRCNNX_x2_16-0-4-1.glsl
  Anime4K_Clamp_Highlights.glsl
  Anime4K_Restore_CNN_M.glsl
  Anime4K_Upscale_CNN_x2_M.glsl
  Anime4K_AutoDownscalePre_x2.glsl
  Anime4K_AutoDownscalePre_x4.glsl
  Anime4K_Upscale_CNN_x2_S.glsl
)

log_step "Locating the mpv shader pack"
pacman -Q mpv-shim-default-shaders >/dev/null 2>&1 \
  || die "mpv-shim-default-shaders is not installed. Run ./install.sh 10 first."

# Derived from the package rather than hardcoded: the upstream install prefix
# has moved before, and a wrong guess here would produce a dangling link that
# only shows up as a missing upscaler during playback.
shader_dir="$(pacman -Ql mpv-shim-default-shaders \
  | awk '$2 ~ /\.glsl$/ { sub(/\/[^\/]*$/, "", $2); print $2; exit }')"
[[ -n ${shader_dir} && -d ${shader_dir} ]] \
  || die "mpv-shim-default-shaders is installed but ships no .glsl files; the shader directory could not be resolved."
log_success "Shader pack found at ${shader_dir}."

if [[ ! -e ${shader_dir}/${REQUIRED_SHADER} ]]; then
  die "${REQUIRED_SHADER} is missing from ${shader_dir}, and mpv.conf applies it automatically to sources below 1440p. The package has renamed it; pick the replacement from:
$(find "${shader_dir}" -maxdepth 1 -name 'ArtCNN*' -printf '    %f\n' | sort)
Then update the glsl-shaders line in dotfiles/desktop/.config/mpv/mpv.conf and this module."
fi

missing_optional=()
for shader in "${OPTIONAL_SHADERS[@]}"; do
  [[ -e ${shader_dir}/${shader} ]] || missing_optional+=("${shader}")
done
if [[ ${#missing_optional[@]} -gt 0 ]]; then
  log_warn "These shaders are named by input.conf but absent from ${shader_dir}: ${missing_optional[*]}. Their keybindings will do nothing until the paths in dotfiles/desktop/.config/mpv/input.conf are corrected."
fi

log_step "Linking the shader pack into the mpv configuration"
if path_has_symlink "${MPV_CONFIG_DIR}"; then
  die "Refusing to write through a symlinked mpv configuration directory: ${MPV_CONFIG_DIR}"
fi
install -d "${MPV_CONFIG_DIR}"
if [[ -e ${SHADER_LINK} && ! -L ${SHADER_LINK} ]]; then
  die "${SHADER_LINK} exists and is not a symlink. Move your own shader collection aside, then rerun ./install.sh 52."
fi
# The link is what keeps the ~~/shaders paths in mpv.conf and input.conf stable
# while pacman updates the shaders underneath them.
ln -sfn -- "${shader_dir}" "${SHADER_LINK}"
log_success "${SHADER_LINK} -> ${shader_dir}"

log_step "Verifying the deployed mpv configuration"
[[ -f ${MPV_CONFIG_DIR}/mpv.conf ]] \
  || die "${MPV_CONFIG_DIR}/mpv.conf is missing. Run ./install.sh 50 first."
# mpv is pointed at a path that cannot exist, which makes it read mpv.conf and
# input.conf and then exit immediately. --idle would parse the same files but
# would then wait for input forever, and playing a real file needs a window.
# The failure to open that path is the expected outcome, so the exit status is
# meaningless here and only mpv's own configuration errors are matched.
mpv_output="$(mpv --vo=null --ao=null --force-window=no \
  "${TMPDIR:-/tmp}/workstation-mpv-probe-$$-does-not-exist" 2>&1 || true)"
if grep -Eq 'Error parsing|option not found' <<< "${mpv_output}"; then
  die "mpv rejected its own configuration: ${mpv_output//$'\n'/; }"
fi
log_success "mpv parses mpv.conf and input.conf without errors."

log_step "Authorising the ff2mpv native messaging host"
ff2mpv_binary="$(command -v ff2mpv-rust 2>/dev/null || command -v ff2mpv 2>/dev/null || true)"
if [[ -z ${ff2mpv_binary} ]]; then
  log_warn "No ff2mpv host binary is installed, so the browser add-on has nothing to talk to. Run ./install.sh 25 to install ff2mpv-rust."
else
  if path_has_symlink "${NATIVE_HOST_DIR}"; then
    die "Refusing to write through a symlinked native messaging directory: ${NATIVE_HOST_DIR}"
  fi
  # Zen reads Firefox's own ~/.mozilla/native-messaging-hosts rather than a
  # directory of its own (zen-browser/desktop#10622), so the manifest goes here
  # even though Zen is the browser that consumes it. Writing it here rather
  # than relying on wherever the AUR package placed it also keeps this working
  # if that package installs only a system-wide copy Zen does not read.
  install -d "${NATIVE_HOST_DIR}"
  manifest_temp="$(mktemp "${TMPDIR:-/tmp}/workstation-ff2mpv-XXXXXX")"
  cat > "${manifest_temp}" <<EOF
{
    "name": "ff2mpv",
    "description": "ff2mpv native messaging host. Managed by workstation; reapply with ./install.sh 52.",
    "path": "${ff2mpv_binary}",
    "type": "stdio",
    "allowed_extensions": ["ff2mpv@yossarian.net"]
}
EOF
  install --mode=0644 "${manifest_temp}" "${NATIVE_HOST_DIR}/ff2mpv.json"
  rm -f -- "${manifest_temp}"
  log_success "${NATIVE_HOST_DIR}/ff2mpv.json points at ${ff2mpv_binary}."
  log_warn "The add-on itself is not installable from here: get it from https://addons.mozilla.org/firefox/addon/ff2mpv/ in Zen."
fi

log_step "Enabling hardware video decoding in Zen"
zen_root=''
for candidate in "${ZEN_CONFIG_ROOT}" "${ZEN_LEGACY_ROOT}"; do
  if [[ -r ${candidate}/profiles.ini ]]; then
    zen_root=${candidate}
    break
  fi
done
if [[ -z ${zen_root} ]]; then
  log_warn "No Zen profile root exists yet (${ZEN_CONFIG_ROOT} or ${ZEN_LEGACY_ROOT}), so Zen has no profile to configure. Start Zen once, then rerun ./install.sh 52."
  log_success "Video pipeline configured apart from Zen's preferences."
  exit 0
fi
if path_has_symlink "${zen_root}"; then
  die "Refusing to write through a symlinked Zen directory: ${zen_root}"
fi

profiles_ini="${zen_root}/profiles.ini"
[[ -r ${profiles_ini} ]] \
  || die "${profiles_ini} is missing, so the Zen profiles cannot be identified. Start Zen once, then rerun ./install.sh 52."

# profiles.ini is the only reliable list: a profile directory is named with a
# random prefix, and stale directories from removed profiles stay on disk.
mapfile -t zen_profiles < <(awk -v root="${zen_root}" '
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

[[ ${#zen_profiles[@]} -gt 0 ]] \
  || die "No profile paths were found in ${profiles_ini}."

# media.hardware-video-decoding.force-enabled is the pref that matters: Firefox
# has shipped VA-API on by default since 137, but it still refuses to use it on
# the NVIDIA stack unless it is forced. media.rdd-ffmpeg.enabled keeps the
# decoder in the RDD process, which is the process MOZ_DISABLE_RDD_SANDBOX
# unsandboxes in hypr-user.lua -- the two settings only work as a pair.
readonly -a ZEN_PREFS=(
  'user_pref("media.hardware-video-decoding.force-enabled", true);'
  'user_pref("media.ffmpeg.vaapi.enabled", true);'
  'user_pref("media.rdd-ffmpeg.enabled", true);'
)

configured_profiles=0
for profile in "${zen_profiles[@]}"; do
  if [[ ! -d ${profile} ]]; then
    log_warn "${profiles_ini} lists a profile directory that does not exist: ${profile}"
    continue
  fi
  if path_has_symlink "${profile}"; then
    log_warn "Skipping a Zen profile reached through a symlink: ${profile}"
    continue
  fi

  user_js="${profile}/user.js"
  profile_temp="$(mktemp "${TMPDIR:-/tmp}/workstation-zen-userjs-XXXXXX")"
  if [[ -f ${user_js} ]]; then
    awk -v begin="${PREF_BEGIN}" -v end="${PREF_END}" '
      $0 == begin { managed = 1; next }
      $0 == end { managed = 0; next }
      !managed { print }
    ' < "${user_js}" > "${profile_temp}"
  else
    : > "${profile_temp}"
  fi
  {
    printf '%s\n' "${PREF_BEGIN}"
    printf '%s\n' "${ZEN_PREFS[@]}"
    printf '%s\n' "${PREF_END}"
  } >> "${profile_temp}"

  if [[ -f ${user_js} ]] && cmp -s -- "${profile_temp}" "${user_js}"; then
    rm -f -- "${profile_temp}"
  else
    install --mode=0644 "${profile_temp}" "${user_js}"
    rm -f -- "${profile_temp}"
  fi
  configured_profiles=$((configured_profiles + 1))
done

[[ ${configured_profiles} -gt 0 ]] \
  || die "None of the profiles listed in ${profiles_ini} could be configured."

log_success "Hardware decoding preferences written to ${configured_profiles} Zen profile(s). Restart Zen, then confirm at about:support that the media decoder reports VA-API."
