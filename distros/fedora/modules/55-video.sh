#!/usr/bin/env bash
set -Eeuo pipefail

readonly DISTRO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT="$(cd -- "${DISTRO_ROOT}/../.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"

# Wires the video upscaler pipeline together: the shader pack installed by
# module 30 is linked into the mpv configuration, the ff2mpv native messaging
# host is authorised for Zen (native or Flatpak), and Zen profiles are pointed
# at hardware video decoding. Everything here is user-level.

readonly MPV_CONFIG_DIR="${HOME}/.config/mpv"
readonly SHADER_LINK="${MPV_CONFIG_DIR}/shaders"
readonly SHADER_PACK_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/default-shader-pack"
readonly NATIVE_HOST_DIR="${HOME}/.mozilla/native-messaging-hosts"
readonly FLATPAK_ZEN_DATA="${HOME}/.var/app/app.zen_browser.zen"
readonly PREF_BEGIN='// >>> workstation video decoding >>>'
readonly PREF_END='// <<< workstation video decoding <<<'

# mpv.conf applies this one through a conditional auto profile, so a rename in
# the pack would silently disable the upscaler on every file below 1440p.
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

require_command mpv

shaders_ok=false
if [[ -d ${SHADER_PACK_DIR}/shaders ]]; then
  shader_dir="${SHADER_PACK_DIR}/shaders"
  if [[ ! -e ${shader_dir}/${REQUIRED_SHADER} ]]; then
    die "${REQUIRED_SHADER} is missing from ${shader_dir}, and mpv.conf applies it automatically to sources below 1440p. The pack renamed it; pick the replacement from:
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
    die "${SHADER_LINK} exists and is not a symlink. Move your own shader collection aside, then rerun ./install.sh 55."
  fi
  # The link is what keeps the ~~/shaders paths in mpv.conf and input.conf stable
  # while module 30 updates the pack underneath them.
  ln -sfn -- "${shader_dir}" "${SHADER_LINK}"
  log_success "${SHADER_LINK} -> ${shader_dir}"
  shaders_ok=true
else
  log_warn "The mpv shader pack is not installed. Enable the 'shaders' feature in step 30, then rerun ./install.sh 55."
fi

log_step "Verifying the deployed mpv configuration"
[[ -f ${MPV_CONFIG_DIR}/mpv.conf ]] \
  || die "${MPV_CONFIG_DIR}/mpv.conf is missing. Run ./install.sh 50 first."
# mpv is pointed at a path that cannot exist, which makes it read mpv.conf and
# input.conf and then exit immediately. The failure to open that path is the
# expected outcome, so the exit status is meaningless here and only mpv's own
# configuration errors are matched.
mpv_output="$(mpv --vo=null --ao=null --force-window=no \
  "${TMPDIR:-/tmp}/workstation-mpv-probe-$$-does-not-exist" 2>&1 || true)"
if grep -Eq 'Error parsing|option not found' <<< "${mpv_output}"; then
  die "mpv rejected its own configuration: ${mpv_output//$'\n'/; }"
fi
log_success "mpv parses mpv.conf and input.conf without errors."

log_step "Authorising the ff2mpv native messaging host"
ff2mpv_binary="${HOME}/.local/bin/ff2mpv-rust"
[[ -x ${ff2mpv_binary} ]] || ff2mpv_binary="$(command -v ff2mpv-rust 2>/dev/null || command -v ff2mpv 2>/dev/null || true)"
if [[ -z ${ff2mpv_binary} ]]; then
  log_warn "No ff2mpv host binary is installed, so the browser add-on has nothing to talk to. Enable the 'ff2mpv' feature in step 30, then rerun ./install.sh 55."
else
  # Zen reads Firefox's own native-messaging directory. The RPM/AUR layout uses
  # ~/.mozilla; the Flatpak sandbox maps the same directory under
  # ~/.var/app/app.zen_browser.zen, so the manifest goes to whichever exists.
  declare -a host_dirs=("${NATIVE_HOST_DIR}")
  if [[ -d ${FLATPAK_ZEN_DATA} ]]; then
    host_dirs+=("${FLATPAK_ZEN_DATA}/.mozilla/native-messaging-hosts")
  fi
  manifest_temp="$(mktemp "${TMPDIR:-/tmp}/workstation-ff2mpv-XXXXXX")"
  for host_dir in "${host_dirs[@]}"; do
    if path_has_symlink "${host_dir}"; then
      die "Refusing to write through a symlinked native messaging directory: ${host_dir}"
    fi
    install -d "${host_dir}"
    cat > "${manifest_temp}" <<EOF
{
    "name": "ff2mpv",
    "description": "ff2mpv native messaging host. Managed by workstation; reapply with ./install.sh 55.",
    "path": "${ff2mpv_binary}",
    "type": "stdio",
    "allowed_extensions": ["ff2mpv@yossarian.net"]
}
EOF
    install --mode=0644 "${manifest_temp}" "${host_dir}/ff2mpv.json"
    log_success "${host_dir}/ff2mpv.json points at ${ff2mpv_binary}."
  done
  rm -f -- "${manifest_temp}"
  if [[ -d ${FLATPAK_ZEN_DATA} ]]; then
    log_warn "For the Flatpak Zen, the host may also need home-directory access (flatseal) so it can launch mpv."
  fi
  log_warn "The add-on itself is not installable from here: get it from https://addons.mozilla.org/firefox/addon/ff2mpv/ in Zen."
fi

log_step "Enabling hardware video decoding in Zen"
# Media prefs apply to every Zen layout this repository supports: the native
# browser (~/.zen) and the Flatpak (~/.var/app/app.zen_browser.zen/.zen or
# .../zen). Each root holds a profiles.ini listing its profiles.
readonly -a ZEN_PREFS=(
  'user_pref("media.hardware-video-decoding.force-enabled", true);'
  'user_pref("media.ffmpeg.vaapi.enabled", true);'
  'user_pref("media.rdd-ffmpeg.enabled", true);'
)

declare -a zen_roots=()
for candidate in "${HOME}/.zen" "${FLATPAK_ZEN_DATA}/.zen" "${FLATPAK_ZEN_DATA}/zen"; do
  [[ -f ${candidate}/profiles.ini ]] || continue
  zen_roots+=("${candidate}")
done

if [[ ${#zen_roots[@]} -eq 0 ]]; then
  log_warn "No Zen profile root was found; start Zen once, then rerun ./install.sh 55."
  if [[ ${shaders_ok} == true ]]; then
    log_success "Video pipeline configured apart from Zen's preferences."
  fi
  exit 0
fi

# media.hardware-video-decoding.force-enabled is the pref that matters: Firefox
# has shipped VA-API on by default since 137, but it still refuses to use it on
# the NVIDIA stack unless it is forced. media.rdd-ffmpeg.enabled keeps the
# decoder in the RDD process, which is the process MOZ_DISABLE_RDD_SANDBOX
# unsandboxes when the session exports it -- the two settings only work as a pair.
configured_profiles=0
for zen_root in "${zen_roots[@]}"; do
  profiles_ini="${zen_root}/profiles.ini"
  log_step "Configuring Zen profiles in ${zen_root}"

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

  if [[ ${#zen_profiles[@]} -eq 0 ]]; then
    log_warn "No profile paths were found in ${profiles_ini}."
    continue
  fi

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
done

[[ ${configured_profiles} -gt 0 ]] \
  || die "None of the Zen profiles could be configured."

log_success "Hardware decoding preferences written to ${configured_profiles} Zen profile(s). Restart Zen, then confirm at about:support that the media decoder reports VA-API."
