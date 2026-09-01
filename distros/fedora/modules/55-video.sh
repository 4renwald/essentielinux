#!/usr/bin/env bash
set -Eeuo pipefail

readonly DISTRO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT="$(cd -- "${DISTRO_ROOT}/../.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"

# Wires the video upscaler pipeline together: the shader pack installed by
# module 30 is linked into the mpv configuration. Everything here is user-level.

readonly MPV_CONFIG_DIR="${HOME}/.config/mpv"
readonly SHADER_LINK="${MPV_CONFIG_DIR}/shaders"
readonly SHADER_PACK_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/default-shader-pack"

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
