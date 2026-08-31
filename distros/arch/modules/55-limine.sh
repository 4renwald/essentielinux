#!/usr/bin/env bash
set -Eeuo pipefail

readonly DISTRO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT="$(cd -- "${DISTRO_ROOT}/../.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"

readonly APPEARANCE_FILE="${DISTRO_ROOT}/etc/limine/appearance.conf"
readonly BEGIN_MARKER='# >>> workstation appearance >>>'
readonly END_MARKER='# <<< workstation appearance <<<'

esp_was_read_only=false
mount_target=''
theme_temp=''

cleanup() {
  local status=$?
  trap - EXIT
  [[ -z ${theme_temp} ]] || rm -f -- "${theme_temp}" "${theme_temp}.body" "${theme_temp}.source"
  if [[ ${esp_was_read_only} == true ]]; then
    if ! as_root mount --options remount,ro --target "${mount_target}"; then
      log_error "Failed to restore the read-only mount on ${mount_target}."
      status=1
    fi
  fi
  exit "${status}"
}
trap cleanup EXIT

[[ -r ${APPEARANCE_FILE} ]] || die "Missing Limine appearance file: ${APPEARANCE_FILE}"

log_step "Installing Limine and its UEFI entry manager"
as_root pacman -S --needed --noconfirm limine efibootmgr

log_step "Locating the active Limine configuration"
declare -a config_candidates=(
  /boot/limine/limine.conf
  /boot/limine.conf
  /boot/EFI/limine/limine.conf
  /boot/EFI/arch-limine/limine.conf
  /boot/EFI/BOOT/limine.conf
  /efi/limine/limine.conf
  /efi/limine.conf
  /efi/EFI/limine/limine.conf
  /efi/EFI/arch-limine/limine.conf
  /efi/EFI/BOOT/limine.conf
)
declare -a configs=()
for candidate in "${config_candidates[@]}"; do
  if as_root test -f "${candidate}"; then
    configs+=("${candidate}")
  fi
done
if [[ ${#configs[@]} -eq 0 ]]; then
  log_warn "No limine.conf was found in the usual locations; nothing was changed."
  log_success "Limine module skipped."
  exit 0
elif [[ ${#configs[@]} -gt 1 ]]; then
  die "Multiple Limine configurations found (${configs[*]}); refusing to guess which one is active."
fi
readonly LIMINE_CONFIG=${configs[0]}

case "${LIMINE_CONFIG}" in
  /boot/*|/boot) mount_target=/boot ;;
  /efi/*|/efi) mount_target=/efi ;;
  *) die "Unable to identify the Limine configuration mount point: ${LIMINE_CONFIG}" ;;
esac

# Keeping the ESP read-only between boot updates limits accidental damage, but
# Limine's configuration and EFI executable live on that filesystem. Make the
# narrowly identified ESP writable for this module and always restore its
# original read-only state in the EXIT trap.
mount_options="$(findmnt --noheadings --output OPTIONS --target "${mount_target}" | head -n1)"
[[ -n ${mount_options} ]] || die "Unable to read mount options for ${mount_target}."
if [[ ,${mount_options}, == *,ro,* ]]; then
  log_step "Temporarily remounting ${mount_target} read-write"
  as_root mount --options remount,rw --target "${mount_target}"
  esp_was_read_only=true
fi

if as_root test -L "${LIMINE_CONFIG}"; then
  die "Refusing to edit a linked bootloader configuration: ${LIMINE_CONFIG}"
fi

log_step "Applying the Tokyo Night Limine palette (${LIMINE_CONFIG})"
theme_temp="$(mktemp "${TMPDIR:-/tmp}/workstation-limine-conf-XXXXXX")"

# Keep sudo failures in the main command flow. Reading through a process
# substitution could otherwise make a failed read look like an empty config.
as_root sed -n '1,$p' "${LIMINE_CONFIG}" > "${theme_temp}.source"

count_entries() { grep -cE '^[[:space:]]*/' -- "$1" || true; }
entries_before="$(count_entries "${theme_temp}.source")"

# Remove the previous managed block and any appearance values it supersedes,
# including wallpaper settings added manually. Boot entries stay in place.
awk -v begin="${BEGIN_MARKER}" -v end="${END_MARKER}" '
  $0 == begin { managed = 1; next }
  $0 == end { managed = 0; next }
  managed { next }
  tolower($0) ~ /^[[:space:]]*(wallpaper|wallpaper_style|backdrop|interface_branding|interface_branding_colou?r|interface_help_colou?r|interface_help_colou?r_bright|term_palette|term_palette_bright|term_background|term_background_bright|term_foreground|term_foreground_bright|term_margin|term_margin_gradient)[[:space:]]*:/ { next }
  { print }
' < "${theme_temp}.source" > "${theme_temp}.body"
{
  printf '%s\n' "${BEGIN_MARKER}"
  sed -n '1,$p' "${APPEARANCE_FILE}"
  printf '%s\n\n' "${END_MARKER}"
  sed -n '1,$p' "${theme_temp}.body"
} > "${theme_temp}"

entries_after="$(count_entries "${theme_temp}")"
[[ ${entries_before} == "${entries_after}" ]] \
  || die "Boot entry count changed from ${entries_before} to ${entries_after}; ${LIMINE_CONFIG} was not modified."

backup="${LIMINE_CONFIG}.workstation-backup"
if ! as_root test -e "${backup}"; then
  as_root cp --no-preserve=ownership,mode -- "${LIMINE_CONFIG}" "${backup}"
  log_warn "Preserved the original configuration as ${backup}."
fi
as_root install --mode=0600 "${theme_temp}" "${LIMINE_CONFIG}"
log_success "Applied Tokyo Night without changing ${entries_after} boot entr(y/ies)."

if [[ ! -d /sys/firmware/efi ]]; then
  log_warn "The system was not booted through UEFI; skipping firmware-entry registration."
  exit 0
fi

log_step "Ensuring a named Limine firmware entry exists"
require_command efibootmgr
require_command findmnt
require_command lsblk

esp_source="$(findmnt --noheadings --output SOURCE --target "${mount_target}" | head -n1)"
esp_source="$(readlink -f -- "${esp_source}")"
[[ -b ${esp_source} ]] || die "The Limine partition source is not a block partition: ${esp_source}"
[[ $(lsblk --noheadings --nodeps --output TYPE "${esp_source}" | xargs) == part ]] \
  || die "The Limine configuration is not stored on a disk partition: ${esp_source}"
parent_name="$(lsblk --noheadings --nodeps --output PKNAME "${esp_source}" | xargs)"
part_number="$(lsblk --noheadings --nodeps --output PARTN "${esp_source}" | xargs)"
[[ -n ${parent_name} && ${part_number} =~ ^[0-9]+$ ]] \
  || die "Unable to derive the disk and partition number for ${esp_source}."
disk="/dev/${parent_name}"

case "$(< /sys/firmware/efi/fw_platform_size)" in
  64) loader_names=(BOOTX64.EFI limine_x64.efi) ;;
  32) loader_names=(BOOTIA32.EFI limine_ia32.efi) ;;
  *) die "Unsupported UEFI firmware bitness." ;;
esac

# Arch's Limine package has used both the generic BOOT*.EFI names and its
# limine_* variant over time. Prefer a loader beside the configuration, then
# check the package's other conventional ESP directories before failing.
declare -a loader_directories=(
  "${LIMINE_CONFIG%/*}"
  "${mount_target}/EFI/limine"
  "${mount_target}/EFI/arch-limine"
  "${mount_target}/EFI/BOOT"
)
loader_file=''
for directory in "${loader_directories[@]}"; do
  for loader_name in "${loader_names[@]}"; do
    candidate="${directory}/${loader_name}"
    if as_root test -f "${candidate}"; then
      loader_file=${candidate}
      break 2
    fi
  done
done
[[ -n ${loader_file} ]] \
  || die "Limine EFI executable was not found in the configuration or conventional ESP directories."

loader_path="${loader_file#"${mount_target}"}"
[[ ${loader_path} == /* ]] || loader_path="/${loader_path}"
loader_path="${loader_path//\//\\}"

normalize_efi_path() {
  local path=${1//\//\\}
  # Firmware paths are case-insensitive. Some efibootmgr versions print
  # escaped separators, so collapse repeated backslashes before comparing.
  path="$(printf '%s\n' "${path}" | tr -s '\\' | tr '[:upper:]' '[:lower:]')"
  printf '%s\n' "${path}"
}

efi_entry_path() {
  sed -n 's/.*[Ff]ile(\([^)]*\)).*/\1/p' <<< "$1"
}

efi_entry_matches_loader() {
  local entry_path
  entry_path="$(efi_entry_path "$1")"
  [[ -n ${entry_path} ]] \
    && [[ $(normalize_efi_path "${entry_path}") == "$(normalize_efi_path "${loader_path}")" ]]
}

limine_entry_visible() {
  local entry
  while IFS= read -r entry; do
    if efi_entry_matches_loader "${entry}"; then
      return 0
    fi
  done < <(efibootmgr -v | awk 'tolower($0) ~ /^boot[[:xdigit:]]{4}\*?[[:space:]]+limine([[:space:]]|$)/ { print }')
  return 1
}

create_limine_entry() {
  as_root efibootmgr \
    --create \
    --disk "${disk}" \
    --part "${part_number}" \
    --label Limine \
    --loader "${loader_path}" \
    --unicode
  limine_entry_visible \
    || die "efibootmgr succeeded, but the Limine entry for ${loader_path} is not visible."
  log_success "Created the Limine firmware entry for ${disk}, partition ${part_number}, loader ${loader_path}."
}

declare -a limine_entries=()
while IFS= read -r entry; do
  [[ -n ${entry} ]] && limine_entries+=("${entry}")
done < <(efibootmgr -v | awk 'tolower($0) ~ /^boot[[:xdigit:]]{4}\*?[[:space:]]+limine([[:space:]]|$)/ { print }')

matching_entry=''
for entry in "${limine_entries[@]}"; do
  if efi_entry_matches_loader "${entry}"; then
    matching_entry=${entry}
    break
  fi
done

if [[ -n ${matching_entry} ]]; then
  log_success "Named Limine firmware entry already targets ${loader_path}."
elif ((${#limine_entries[@]} > 0)); then
  # A previous Limine installation may use a different valid path (for
  # example limine_x64.efi instead of BOOTX64.EFI). Keep the existing entry
  # rather than rewriting a user's boot order or creating a duplicate label.
  existing_path="$(efi_entry_path "${limine_entries[0]}")"
  if [[ -n ${existing_path} ]]; then
    log_warn "A named Limine entry already uses ${existing_path}; keeping it unchanged."
  else
    log_warn "A named Limine entry exists but its loader path could not be read; keeping it unchanged."
  fi
else
  create_limine_entry
fi

log_success "Limine is themed and registered; the existing UEFI OS fallback was retained."
