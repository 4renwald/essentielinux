#!/usr/bin/env bash
set -Eeuo pipefail

readonly DISTRO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT="$(cd -- "${DISTRO_ROOT}/../.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"

# Each block is a feature id from packages/upstream.txt and can be deselected
# per machine through the installer's customize menus.
feature_enabled() {
  ! selection_is_skipped upstream "$1"
}

readonly WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/workstation-upstream-XXXXXX")"
readonly KEEPER_VERSION=18.6.1-1
readonly KEEPER_SHA256=40a085a2c4bf8283dd10035fec7657d94aa5f7e64c19a4de1f521d7a133b49b7
cleanup() {
  find "${WORK_DIR}" -depth -mindepth 1 -delete 2>/dev/null || true
  rmdir "${WORK_DIR}" 2>/dev/null || true
}
trap cleanup EXIT

install -d "${HOME}/.local/bin"

install_archive_binary() {
  local repository=$1 asset_pattern=$2 file_pattern=$3 install_name=$4
  local url archive extract found
  url="$(github_asset_url "${repository}" "${asset_pattern}")" \
    || die "No official ${repository} release asset matched ${asset_pattern}."
  archive="${WORK_DIR}/${install_name}.archive"
  extract="${WORK_DIR}/${install_name}"
  install -d "${extract}"
  download "${url}" "${archive}"
  tar -xf "${archive}" -C "${extract}"
  found="$(find "${extract}" -type f -name "${file_pattern}" -print -quit)"
  [[ -n ${found} ]] || die "The ${repository} release did not contain ${file_pattern}."
  install --mode=0755 "${found}" "${HOME}/.local/bin/${install_name}"
  log_success "Installed ${install_name} from ${repository}."
}

if feature_enabled codex || feature_enabled opencode || feature_enabled lazygit \
  || feature_enabled starship || feature_enabled spicetify; then
  log_step 'Installing approved official upstream CLI releases'
  if feature_enabled codex; then
    install_archive_binary openai/codex \
      '^codex-x86_64-unknown-linux-musl[.]tar[.]gz$' 'codex*' codex
  fi
  if feature_enabled opencode; then
    install_archive_binary anomalyco/opencode \
      '^opencode-linux-x64[.]tar[.]gz$' opencode opencode
  fi
  if feature_enabled lazygit; then
    install_archive_binary jesseduffield/lazygit \
      '^lazygit_[0-9.]+_linux_x86_64[.]tar[.]gz$' lazygit lazygit
  fi
  if feature_enabled starship; then
    install_archive_binary starship/starship \
      '^starship-x86_64-unknown-linux-musl[.]tar[.]gz$' starship starship
  fi
  if feature_enabled spicetify; then
    install_archive_binary spicetify/cli \
      '^spicetify-[0-9.]+-linux-amd64[.]tar[.]gz$' spicetify spicetify
  fi
fi

if feature_enabled bluetui; then
  log_step 'Installing bluetui'
  bluetui_url="$(github_asset_url pythops/bluetui '^bluetui-x86_64-linux-musl$')" \
    || die 'Unable to find the official bluetui x86_64 release.'
  download "${bluetui_url}" "${WORK_DIR}/bluetui"
  install --mode=0755 "${WORK_DIR}/bluetui" "${HOME}/.local/bin/bluetui"
fi

if feature_enabled hyprmod; then
  log_step 'Installing hyprmod (GTK4 settings app for Hyprland)'
  # hyprmod is a PyGObject application and pycairo ships no Linux wheels, so
  # building its venv with uv or pipx alone would compile C extensions. The
  # venv instead reuses Fedora's own python3-gobject and python3-cairo.
  as_root dnf -y install pipx python3-gobject
  pipx install --force --system-site-packages \
    git+https://github.com/BlueManCZ/hyprmod.git
  "${HOME}/.local/bin/hyprmod" --install
  log_success 'hyprmod installed; desktop entry registered.'
fi

if feature_enabled fonts; then
  log_step 'Installing Nerd Fonts from official releases'
  system_font_dir=/usr/local/share/fonts/managed-workstation
  as_root install -d --mode=0755 "${system_font_dir}"
  for font_asset in JetBrainsMono NerdFontsSymbolsOnly; do
    url="$(github_asset_url ryanoasis/nerd-fonts "^${font_asset}[.]tar[.]xz$")"
    archive="${WORK_DIR}/${font_asset}.tar.xz"
    extract="${WORK_DIR}/${font_asset}"
    install -d "${extract}"
    download "${url}" "${archive}"
    tar -xf "${archive}" -C "${extract}"
    while IFS= read -r font; do
      as_root install --mode=0644 "${font}" "${system_font_dir}/${font##*/}"
    done < <(find "${extract}" -type f -name '*.ttf' -print)
  done
  as_root fc-cache -f
fi

if feature_enabled bibata; then
  log_step 'Installing the Bibata cursor from official releases'
  bibata_url="$(github_asset_url ful1e5/Bibata_Cursor '^Bibata-Modern-Classic[.]tar[.]xz$')"
  download "${bibata_url}" "${WORK_DIR}/bibata.tar.xz"
  tar -xf "${WORK_DIR}/bibata.tar.xz" -C "${WORK_DIR}"
  bibata_dir="$(find "${WORK_DIR}" -maxdepth 2 -type d -name Bibata-Modern-Classic -print -quit)"
  [[ -n ${bibata_dir} ]] || die 'Bibata release layout was not recognized.'
  if as_root test -e /usr/share/icons/Bibata-Modern-Classic; then
    log_warn 'The system Bibata-Modern-Classic cursor already exists; leaving it in place.'
  else
    as_root cp -a --no-preserve=ownership -- "${bibata_dir}" /usr/share/icons/Bibata-Modern-Classic
  fi
  as_root fc-cache -f
fi

# The shader pack is what module 55 links into ~/.config/mpv/shaders and what
# mpv.conf and input.conf name: ArtCNN, Anime4K, FSRCNNX and friends. Upstream
# is a plain Git repository of shader files rather than release tarballs, so it
# is cloned and updated like the wallpaper collection.
if feature_enabled shaders; then
  readonly SHADER_PACK_REPOSITORY='https://github.com/iwalton3/default-shader-pack.git'
  readonly SHADER_PACK_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/default-shader-pack"
  if [[ -d ${SHADER_PACK_DIR}/.git ]]; then
    origin="$(git -C "${SHADER_PACK_DIR}" remote get-url origin 2>/dev/null || true)"
    if [[ ${origin%.git} == ${SHADER_PACK_REPOSITORY%.git} ]]; then
      git -C "${SHADER_PACK_DIR}" pull --ff-only
      log_success 'mpv shader pack updated.'
    else
      log_warn "${SHADER_PACK_DIR} is a different repository; leaving it untouched."
    fi
  elif [[ -e ${SHADER_PACK_DIR} ]]; then
    log_warn "${SHADER_PACK_DIR} already exists and is not a Git checkout; leaving it untouched."
  else
    git clone --depth 1 "${SHADER_PACK_REPOSITORY}" "${SHADER_PACK_DIR}"
    log_success "mpv shader pack cloned to ${SHADER_PACK_DIR}."
  fi
fi

if feature_enabled ff2mpv; then
  log_step 'Installing the ff2mpv native messaging host'
  ff2mpv_url="$(github_asset_url ryze312/ff2mpv-rust '^ff2mpv-rust-x86_64-unknown-linux-musl$')" \
    || die 'Unable to find the official ff2mpv-rust x86_64 release.'
  download "${ff2mpv_url}" "${WORK_DIR}/ff2mpv-rust"
  install --mode=0755 "${WORK_DIR}/ff2mpv-rust" "${HOME}/.local/bin/ff2mpv-rust"
  log_success "Installed ff2mpv-rust to ${HOME}/.local/bin."
fi

if feature_enabled flatpaks; then
  log_step 'Installing the approved Flathub applications'
  read_manifest "${DISTRO_ROOT}/packages/flatpaks.txt"
  apply_selection flatpaks
  if ((${#PACKAGES[@]} > 0)); then
    as_root flatpak install --system --noninteractive -y flathub "${PACKAGES[@]}"
  else
    log_info 'No Flathub applications selected; skipping.'
  fi
fi

if feature_enabled chatgpt; then
  log_step 'Installing the official ChatGPT desktop RPM for Fedora'
  # dnf installs straight from the URL into its own cache; staging large RPMs
  # in WORK_DIR piled up until the module exited and exhausted /tmp (curl
  # error 23 on tmpfs).
  as_root dnf -y install \
    'https://persistent.oaistatic.com/codex-app-prod/linux/rpm/latest/chatgpt.x86_64.rpm'
fi

if feature_enabled keeper; then
  log_step "Installing the official Keeper Password Manager ${KEEPER_VERSION} RPM"
  keeper_rpm="${WORK_DIR}/keeperpasswordmanager-${KEEPER_VERSION}.x86_64.rpm"
  download \
    "https://www.keepersecurity.com/desktop_electron/Linux/repo/rpm/keeperpasswordmanager-${KEEPER_VERSION}.x86_64.rpm" \
    "${keeper_rpm}"
  printf '%s  %s\n' "${KEEPER_SHA256}" "${keeper_rpm}" | sha256sum --check --status \
    || die 'The Keeper RPM checksum did not match the audited vendor package.'
  as_root dnf -y install "${keeper_rpm}"
  rm -f -- "${keeper_rpm}"
fi

if feature_enabled opencode-desktop; then
  log_step 'Installing the official OpenCode desktop RPM'
  opencode_desktop_rpm="$(github_asset_url anomalyco/opencode \
    '^opencode-desktop-linux-x86_64[.]rpm$')" \
    || die 'Unable to find the official opencode-desktop-linux-x86_64 release asset.'
  # The desktop RPM is named `opencode`, but it installs its GUI as
  # `ai.opencode.desktop`; it does not overwrite the separate OpenCode CLI in
  # ~/.local/bin/opencode installed above.
  as_root dnf -y install "${opencode_desktop_rpm}"
fi

if feature_enabled megasync; then
  log_step 'Installing the official MEGAsync RPM for Fedora 44'
  as_root dnf -y install \
    'https://mega.nz/linux/repo/Fedora_44/x86_64/megasync-Fedora_44.x86_64.rpm'
fi

if feature_enabled proton-mail; then
  log_step 'Installing the official Proton Mail desktop RPM'
  as_root dnf -y install \
    'https://proton.me/download/mail/linux/1.13.4/ProtonMail-desktop-beta.rpm'
fi

if feature_enabled vm-curator; then
  log_step 'Installing the official vm-curator RPM'
  vm_curator_url="$(github_asset_url mroboff/vm-curator '^vm-curator-[0-9.]+-1[.]x86_64[.]rpm$')" \
    || die 'Unable to find the official vm-curator x86_64 RPM release.'
  as_root dnf -y install "${vm_curator_url}"
fi

log_success 'Enabled upstream tools, fonts, cursor, and vendor RPMs are installed.'
