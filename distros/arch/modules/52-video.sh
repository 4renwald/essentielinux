#!/usr/bin/env bash
set -Eeuo pipefail

readonly DISTRO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT="$(cd -- "${DISTRO_ROOT}/../.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"

# Everything module 50 could not deploy as a static file, because it depends on
# a path only this machine knows: where pacman put the shader pack.

readonly MPV_CONFIG_DIR="${HOME}/.config/mpv"
readonly SHADER_LINK="${MPV_CONFIG_DIR}/shaders"

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
