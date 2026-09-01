#!/usr/bin/env bash
set -Eeuo pipefail

readonly DISTRO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT="$(cd -- "${DISTRO_ROOT}/../.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"

readonly APPEARANCE_FILE="${DISTRO_ROOT}/etc/limine/appearance.conf"
readonly BEGIN_MARKER='# >>> workstation appearance >>>'
readonly END_MARKER='# <<< workstation appearance <<<'

declare -a remounted_targets=()
declare -a temp_files=()

cleanup() {
  local status=$? target
  trap - EXIT
  ((${#temp_files[@]} == 0)) || rm -f -- "${temp_files[@]}"
  for target in "${remounted_targets[@]}"; do
    if ! as_root mount --options remount,ro --target "${target}"; then
      log_error "Failed to restore the read-only mount on ${target}."
      status=1
    fi
  done
  exit "${status}"
}
trap cleanup EXIT

# Creates a scratch file, registers it for cleanup, and returns it in
# TEMP_FILE. A command substitution would run in a subshell and lose the
# registration, so the caller reads the variable instead.
make_temp_file() {
  TEMP_FILE="$(mktemp "${TMPDIR:-/tmp}/workstation-limine-XXXXXX")"
  temp_files+=("${TEMP_FILE}")
}

[[ -r ${APPEARANCE_FILE} ]] || die "Missing Limine appearance file: ${APPEARANCE_FILE}"

log_step "Installing Limine and its UEFI entry manager"
as_root pacman -S --needed --noconfirm limine efibootmgr

require_command findmnt
require_command lsblk

# `findmnt --target` has to resolve the path it is asked about, and the ESP is
# routinely mounted root-only (archinstall's fmask/dmask leave /boot without
# search permission for anyone else). Run these lookups through the same
# elevation every other access to these paths already uses, or the module
# cannot even name the filesystem holding a config it just read as root.
mount_field_of() {
  local field=$1 path=$2 value
  value="$(as_root findmnt --noheadings --first-only --output "${field}" --target "${path}")" \
    || return 1
  [[ -n ${value} ]] || return 1
  printf '%s\n' "${value}"
}

mount_point_of() {
  mount_field_of TARGET "$1"
}

# Keeping the ESP read-only between boot updates limits accidental damage, but
# Limine's configuration and EFI executable live on that filesystem. Make it
# writable for this module; the EXIT trap always restores every mount it
# touched, whether the module succeeds or dies.
ensure_mount_writable() {
  local target=$1 options existing
  for existing in "${remounted_targets[@]}"; do
    if [[ ${existing} == "${target}" ]]; then
      return 0
    fi
  done
  options="$(mount_field_of OPTIONS "${target}")" \
    || die "Unable to read mount options for ${target}."
  if [[ ,${options}, == *,ro,* ]]; then
    log_step "Temporarily remounting ${target} read-write"
    as_root mount --options remount,rw --target "${target}"
    remounted_targets+=("${target}")
  fi
}

# Bootloader files sit on the ESP, which is FAT: its driver refuses any mode
# that conflicts with the filesystem's fmask/dmask mount options, so
# `install --mode=...` fails there with EPERM even as root. Copy into place
# without setting a mode, staging through a name on the same filesystem so a
# boot configuration is never left half-written.
write_boot_file() {
  local source=$1 target=$2 staged="$2.workstation-new"
  as_root cp --no-preserve=mode,ownership -- "${source}" "${staged}" \
    || die "Could not stage the new contents of ${target}."
  as_root mv -f -- "${staged}" "${target}" \
    || die "Could not replace ${target}."
}

log_step "Locating the active Limine configuration"
# Limine picks the first configuration it finds while scanning the boot volume,
# and which one that is depends on the firmware's report of where it loaded
# from (see Limine's CONFIG.md). Rather than guess the winner, every candidate
# that exists gets the same appearance block, which leaves the same menu no
# matter which one Limine settles on.
declare -a config_candidates=(
  /boot/limine/limine.conf
  /boot/limine.conf
  /boot/EFI/limine/limine.conf
  /boot/EFI/arch-limine/limine.conf
  /boot/EFI/BOOT/limine.conf
  /boot/efi/limine/limine.conf
  /boot/efi/limine.conf
  /boot/efi/EFI/limine/limine.conf
  /boot/efi/EFI/arch-limine/limine.conf
  /boot/efi/EFI/BOOT/limine.conf
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
if ((${#configs[@]} == 0)); then
  log_warn "No limine.conf was found in the usual locations; nothing was changed."
  log_success "Limine module skipped."
  exit 0
fi

count_entries() { grep -cE '^[[:space:]]*/' -- "$1" || true; }

apply_appearance() {
  local config=$1 mount_target entries_before entries_after
  local source_copy body_copy staged_copy backup

  if as_root test -L "${config}"; then
    die "Refusing to edit a linked bootloader configuration: ${config}"
  fi
  mount_target="$(mount_point_of "${config}")" \
    || die "Unable to identify the filesystem holding ${config}."
  ensure_mount_writable "${mount_target}"

  log_step "Applying the Tokyo Night Limine palette (${config})"
  make_temp_file; source_copy=${TEMP_FILE}
  make_temp_file; body_copy=${TEMP_FILE}
  make_temp_file; staged_copy=${TEMP_FILE}

  # Keep sudo failures in the main command flow. Reading through a process
  # substitution could otherwise make a failed read look like an empty config.
  as_root sed -n '1,$p' "${config}" > "${source_copy}"
  entries_before="$(count_entries "${source_copy}")"

  # Remove the previous managed block and any appearance values it supersedes,
  # including wallpaper settings added manually. Boot entries stay in place.
  awk -v begin="${BEGIN_MARKER}" -v end="${END_MARKER}" '
    $0 == begin { managed = 1; next }
    $0 == end { managed = 0; next }
    managed { next }
    tolower($0) ~ /^[[:space:]]*(wallpaper|wallpaper_style|backdrop|interface_branding|interface_branding_colou?r|interface_help_colou?r|interface_help_colou?r_bright|term_palette|term_palette_bright|term_background|term_background_bright|term_foreground|term_foreground_bright|term_margin|term_margin_gradient)[[:space:]]*:/ { next }
    # The managed block is written back with one blank line after it. Dropping
    # the blank lines the previous block left behind keeps a rerun byte-for-byte
    # identical instead of growing the gap by one line every time.
    !started && $0 ~ /^[[:space:]]*$/ { next }
    { started = 1; print }
  ' < "${source_copy}" > "${body_copy}"
  {
    printf '%s\n' "${BEGIN_MARKER}"
    sed -n '1,$p' "${APPEARANCE_FILE}"
    printf '%s\n\n' "${END_MARKER}"
    sed -n '1,$p' "${body_copy}"
  } > "${staged_copy}"

  entries_after="$(count_entries "${staged_copy}")"
  [[ ${entries_before} == "${entries_after}" ]] \
    || die "Boot entry count changed from ${entries_before} to ${entries_after}; ${config} was not modified."

  if cmp -s -- "${staged_copy}" "${source_copy}"; then
    log_success "${config} already carries the Tokyo Night palette."
    return 0
  fi

  backup="${config}.workstation-backup"
  if ! as_root test -e "${backup}"; then
    as_root cp --no-preserve=ownership,mode -- "${config}" "${backup}"
    log_warn "Preserved the original configuration as ${backup}."
  fi
  write_boot_file "${staged_copy}" "${config}"
  log_success "Applied Tokyo Night to ${config} without changing ${entries_after} boot entr(y/ies)."
}

for config in "${configs[@]}"; do
  apply_appearance "${config}"
done

if [[ ! -d /sys/firmware/efi ]]; then
  log_warn "The system was not booted through UEFI; skipping firmware-entry registration."
  exit 0
fi

log_step "Ensuring a Limine firmware entry exists"
require_command efibootmgr

# Arch's Limine package has used both the generic BOOT*.EFI names and its
# limine_* variant over time, and archinstall deploys the generic name into
# EFI/arch-limine or EFI/BOOT depending on whether a removable install was
# chosen. Cover all of them rather than assuming one layout.
case "$(uname -m)" in
  aarch64)
    loader_names=(BOOTAA64.EFI limine_aa64.efi)
    ;;
  *)
    case "$(< /sys/firmware/efi/fw_platform_size)" in
      64) loader_names=(BOOTX64.EFI limine_x64.efi) ;;
      32) loader_names=(BOOTIA32.EFI limine_ia32.efi) ;;
      *) die "Unsupported UEFI firmware bitness." ;;
    esac
    ;;
esac

# A file named BOOTX64.EFI is not necessarily Limine's: EFI/BOOT is the
# firmware's generic fallback path and any bootloader may own it. Registering
# somebody else's loader under a Limine entry would be worse than registering
# nothing, so confirm the binary identifies itself as Limine.
file_is_limine() {
  as_root grep -qa -- 'Limine' "$1"
}

# Every filesystem worth searching for the Limine EFI binary: the mounted FAT
# filesystems (the ESP is one of them) plus the directories holding the
# configurations found above, since the Arch package and archinstall both keep
# the binary beside its configuration.
esp_search_roots() {
  local config
  {
    findmnt --noheadings --output TARGET --types vfat 2>/dev/null || true
    for config in "${configs[@]}"; do
      printf '%s\n' "${config%/*}"
    done
  } | awk 'NF' | sort -u
}

find_limine_loader() {
  local root directory name candidate fallback=''
  local -a roots=()
  mapfile -t roots < <(esp_search_roots)

  for root in "${roots[@]}"; do
    for directory in \
      "${root}" \
      "${root}/EFI/limine" \
      "${root}/EFI/arch-limine" \
      "${root}/EFI/Limine" \
      "${root}/EFI/BOOT"; do
      for name in "${loader_names[@]}"; do
        candidate="${directory}/${name}"
        as_root test -f "${candidate}" || continue
        if file_is_limine "${candidate}"; then
          LOADER_FILE=${candidate}
          return 0
        fi
        # EFI/BOOT holds the firmware's generic fallback under a generic
        # name, so an unrecognised binary there belongs to another
        # bootloader as often as not. Only keep a fallback that a
        # Limine-specific directory or file name vouches for.
        if [[ -z ${fallback} && ( ${directory,,} == *limine* || ${name,,} == limine_* ) ]]; then
          fallback=${candidate}
        fi
      done
    done
  done

  [[ -n ${fallback} ]] || return 1
  log_warn "No EFI executable identifies itself as Limine; falling back to ${fallback}, which a Limine-specific path names."
  LOADER_FILE=${fallback}
}

find_limine_loader \
  || die "Limine EFI executable was not found on the EFI system partition or beside a Limine configuration."
readonly LOADER_FILE

esp_mount_target="$(mount_point_of "${LOADER_FILE}")" \
  || die "Unable to identify the filesystem holding ${LOADER_FILE}."

# A firmware entry addresses the loader by its path inside the EFI system
# partition, so that path is only meaningful when the file really sits on one.
# On anything else the theming above still stands and whatever entry the
# machine already boots from is left alone, which beats registering an entry
# the firmware cannot follow.
esp_fstype="$(mount_field_of FSTYPE "${esp_mount_target}")" || esp_fstype=''
if [[ ${esp_fstype} != vfat ]]; then
  log_warn "${LOADER_FILE} is on a ${esp_fstype:-unknown} filesystem rather than an EFI system partition; leaving the firmware boot entries untouched."
  exit 0
fi

loader_path="${LOADER_FILE#"${esp_mount_target}"}"
[[ ${loader_path} == /* ]] || loader_path="/${loader_path}"
loader_path="${loader_path//\//\\}"
readonly loader_path

esp_source="$(mount_field_of SOURCE "${esp_mount_target}")" \
  || die "Unable to read the block device behind ${esp_mount_target}."
esp_source="$(readlink -f -- "${esp_source}")"
[[ -b ${esp_source} ]] || die "The Limine partition source is not a block partition: ${esp_source}"
[[ $(lsblk --noheadings --nodeps --output TYPE "${esp_source}" | xargs) == part ]] \
  || die "The Limine EFI executable is not stored on a disk partition: ${esp_source}"
parent_name="$(lsblk --noheadings --nodeps --output PKNAME "${esp_source}" | xargs)"
part_number="$(lsblk --noheadings --nodeps --output PARTN "${esp_source}" | xargs)"
[[ -n ${parent_name} && ${part_number} =~ ^[0-9]+$ ]] \
  || die "Unable to derive the disk and partition number for ${esp_source}."
disk="/dev/${parent_name}"

normalize_efi_path() {
  local path=${1//\//\\}
  # Firmware paths are case-insensitive. Some efibootmgr versions print
  # escaped separators, so collapse repeated backslashes before comparing.
  path="$(printf '%s\n' "${path}" | tr -s '\\' | tr '[:upper:]' '[:lower:]')"
  printf '%s\n' "${path}"
}

# efibootmgr renders device paths through libefivar, and the shape of a file
# path node changed with it. Older releases wrapped it, File(\EFI\BOOT\BOOTX64.EFI);
# current ones print it bare, joined to the node before it by a slash:
#   HD(1,GPT,<guid>,0x800,0x200000)/\EFI\BOOT\BOOTX64.EFI
# Read both forms, or on a current Arch install every entry looks pathless and
# no entry can ever be recognised.
efi_entry_path() {
  local path
  path="$(sed -n 's/.*[Ff]ile(\([^)]*\)).*/\1/p' <<< "$1")"
  if [[ -z ${path} ]]; then
    path="$(sed -n 's|.*)/\(\\[^[:space:]]*\).*|\1|p' <<< "$1")"
  fi
  printf '%s\n' "${path}"
}

# The human-readable label of an entry, without the Boot#### prefix and
# without the device path efibootmgr appends. The device path of a Limine
# install contains "limine" itself, so a label test that reads the whole line
# would call every entry on the ESP a Limine entry.
efi_entry_label() {
  local label
  label="$(sed -E 's/^Boot[[:xdigit:]]{4}\*?[[:space:]]+//' <<< "$1")"
  label="${label%%$'\t'*}"
  label="${label%%HD(*}"
  label="${label%%PciRoot(*}"
  label="${label%%VenHw(*}"
  label="${label%%FvVol(*}"
  printf '%s\n' "${label%"${label##*[![:space:]]}"}"
}

efi_boot_entries() {
  awk '/^Boot[[:xdigit:]][[:xdigit:]][[:xdigit:]][[:xdigit:]][*]?[[:space:]]/ { print }' \
    <<< "${efibootmgr_output}"
}

entry_on_this_partition() {
  # Two disks can each hold a \EFI\BOOT\BOOTX64.EFI, so an identical path is
  # only the same loader when it is also on this partition.
  [[ -z ${esp_partuuid} ]] || [[ ${1,,} == *"${esp_partuuid}"* ]]
}

entry_path_matches_loader() {
  local entry_path
  # When no entry in the listing yields a readable path, efibootmgr is
  # rendering device paths in a shape this module cannot parse. Registering a
  # duplicate entry, or failing the step, would both be worse than trusting
  # the label and the partition, so treat the path as agreeing.
  [[ ${efi_paths_readable} == true ]] || return 0
  entry_path="$(efi_entry_path "$1")"
  [[ -n ${entry_path} ]] || return 1
  [[ $(normalize_efi_path "${entry_path}") == "$(normalize_efi_path "${loader_path}")" ]]
}

# The entry this module is responsible for: one that boots this loader from
# this partition under a label naming Limine. The label matters as much as the
# path, because the firmware's generic fallback entry ("UEFI OS") points at
# \EFI\BOOT\BOOTX64.EFI too whenever Limine is installed in removable mode.
# Matching that one would leave the machine with no named Limine entry at all.
# The label test is loose on purpose: archinstall calls its own entry
# "Arch Linux Limine Bootloader".
entry_is_limine_for_loader() {
  local entry=$1
  [[ $(efi_entry_label "${entry}") == *[Ll]imine* ]] || return 1
  entry_on_this_partition "${entry}" || return 1
  entry_path_matches_loader "${entry}"
}

efibootmgr_output="$(as_root efibootmgr -v)" \
  || die "Could not read the firmware boot entries."
esp_partuuid="$(lsblk --noheadings --nodeps --output PARTUUID "${esp_source}" | xargs)"
esp_partuuid="${esp_partuuid,,}"
# Older efibootmgr releases print device paths without the partition GUID.
# Only require the GUID to appear in an entry when this release prints it.
if [[ -n ${esp_partuuid} && ${efibootmgr_output,,} != *"${esp_partuuid}"* ]]; then
  esp_partuuid=''
fi

efi_paths_readable=false
while IFS= read -r entry; do
  if [[ -n $(efi_entry_path "${entry}") ]]; then
    efi_paths_readable=true
    break
  fi
done < <(efi_boot_entries)
if [[ ${efi_paths_readable} == false ]]; then
  log_warn 'This efibootmgr prints device paths in an unrecognised form; matching boot entries by label and partition instead.'
fi

matching_entry=''
labelled_entry=''
while IFS= read -r entry; do
  [[ -n ${entry} ]] || continue
  if entry_is_limine_for_loader "${entry}"; then
    matching_entry=${entry}
    break
  fi
  if [[ -z ${labelled_entry} && $(efi_entry_label "${entry}") == *[Ll]imine* ]]; then
    labelled_entry=${entry}
  fi
done < <(efi_boot_entries)

if [[ -n ${matching_entry} ]]; then
  log_success "The firmware entry \"$(efi_entry_label "${matching_entry}")\" already boots ${loader_path}."
elif [[ -n ${labelled_entry} ]]; then
  # A Limine installation elsewhere on the machine (another disk, or the
  # limine_x64.efi name) already has an entry. Adding a second one would
  # reorder somebody's boot menu for no gain, so leave it alone and say so.
  log_warn "The firmware entry \"$(efi_entry_label "${labelled_entry}")\" already boots $(efi_entry_path "${labelled_entry}"); keeping it unchanged instead of adding a second one for ${loader_path}."
else
  as_root efibootmgr \
    --create \
    --disk "${disk}" \
    --part "${part_number}" \
    --label Limine \
    --loader "${loader_path}" \
    --unicode \
    || die "efibootmgr could not create the Limine entry for ${disk} partition ${part_number}."
  efibootmgr_output="$(as_root efibootmgr -v)" \
    || die "Could not re-read the firmware boot entries."
  matching_entry=''
  while IFS= read -r entry; do
    [[ -n ${entry} ]] || continue
    if entry_is_limine_for_loader "${entry}"; then
      matching_entry=${entry}
      break
    fi
  done < <(efi_boot_entries)
  [[ -n ${matching_entry} ]] \
    || die "efibootmgr succeeded, but the Limine entry for ${loader_path} is not visible."
  log_success "Created the Limine firmware entry for ${disk}, partition ${part_number}, loader ${loader_path}."
fi

log_success "Limine is themed and registered; the existing UEFI OS fallback was retained."
