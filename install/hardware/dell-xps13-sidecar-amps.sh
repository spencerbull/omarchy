# Enable the CS35L56 sidecar speaker amplifiers on the Dell XPS 13 DX13260.
# Linux commit efd80de2de9d adds this exact PCI quirk upstream. Until every
# installed kernel contains it, the read-only module override selects the same
# SOC_SDW_SIDECAR_AMPS path without replacing the kernel or audio firmware.

xps13_dmi_vendor="/sys/class/dmi/id/sys_vendor"
xps13_dmi_sku="/sys/class/dmi/id/product_sku"
xps13_modules_root="/usr/lib/modules"
xps13_managed_conf="/etc/modprobe.d/dell-xps13-dx13260-sidecar-amps.conf"
xps13_kernel_hook="/etc/pacman.d/hooks/95-omarchy-xps13-sidecar-amps.hook"
xps13_active_quirk="/sys/module/snd_soc_sof_sdw/parameters/quirk"
xps13_repair_marker="/var/lib/omarchy/migrations/1786510911"
xps13_cleanup_pending="/var/lib/omarchy/migrations/1786510911-cleanup-pending"
xps13_lock="/run/lock/omarchy-xps13-sidecar-amps.lock"
xps13_managed_begin="# BEGIN Omarchy Dell XPS 13 DX13260 sidecar amps"
xps13_managed_end="# END Omarchy Dell XPS 13 DX13260 sidecar amps"
xps13_managed_block="$xps13_managed_begin
# Temporary override until the installed kernel contains Linux efd80de2de9d.
options snd_soc_sof_sdw quirk=65536
$xps13_managed_end"
xps13_legacy_block="# Temporary compatibility override for Dell XPS 13 DX13260, subsystem 1028:0e53.
# Linux mainline commit efd80de2de9d enables the same SOC_SDW_SIDECAR_AMPS
# quirk natively. Remove this file after upgrading to a kernel containing it.
options snd_soc_sof_sdw quirk=65536"
xps13_kernel_hook_contents="[Trigger]
Operation = Install
Operation = Upgrade
Operation = Remove
Type = Path
Target = usr/lib/modules/*/kernel/sound/soc/intel/boards/snd-soc-sof-sdw.ko*

[Action]
Description = Reconciling the Dell XPS 13 speaker amplifier quirk...
When = PostTransaction
Exec = /usr/bin/bash /usr/share/omarchy/install/hardware/dell-xps13-sidecar-amps.sh --kernel-updated"

xps13_sidecar_hardware_matches() {
  local vendor sku
  vendor="$(cat "$xps13_dmi_vendor" 2>/dev/null || true)"
  sku="$(cat "$xps13_dmi_sku" 2>/dev/null || true)"
  [[ $vendor == "Dell Inc." && $sku == "0E53" ]]
}

xps13_release_has_native_quirk() {
  local release="$1" major minor rc

  [[ $release =~ ^([0-9]+)\.([0-9]+) ]] || return 1
  major="${BASH_REMATCH[1]}"
  minor="${BASH_REMATCH[2]}"

  if ((major > 7 || (major == 7 && minor > 2))); then
    return 0
  fi
  ((major == 7 && minor == 2)) || return 1

  # efd80de2de9d first appears in v7.2-rc5. Official Arch packages use the
  # stable release, but keep prerelease kernels conservative before that tag.
  if [[ $release =~ ^7\.2(\.0)?[-.]?rc([0-9]+) ]]; then
    rc="${BASH_REMATCH[2]}"
    ((rc >= 5))
  else
    return 0
  fi
}

xps13_all_installed_kernels_are_native() {
  local module release
  local -a modules=()

  [[ -d $xps13_modules_root ]] || return 1
  mapfile -d '' modules < <(
    find "$xps13_modules_root" -type f \
      -path '*/kernel/sound/soc/intel/boards/snd-soc-sof-sdw.ko*' -print0
  )
  ((${#modules[@]} > 0)) || return 1

  for module in "${modules[@]}"; do
    release="${module#"$xps13_modules_root"/}"
    release="${release%%/*}"
    xps13_release_has_native_quirk "$release" || return 1
  done
}

xps13_effective_quirks() {
  local config directive module options option
  config="$(modprobe --showconfig)" || return 3

  while read -r directive module options; do
    [[ $directive == "options" ]] || continue
    module="${module//-/_}"
    [[ $module == "snd_soc_sof_sdw" ]] || continue
    for option in $options; do
      [[ $option == quirk=* ]] && printf '%s\n' "${option#quirk=}"
    done
  done <<<"$config"
  return 0
}

xps13_remove_managed_override() {
  local begin_line end_line tmp
  [[ -f $xps13_managed_conf ]] || return 1

  if [[ $(<"$xps13_managed_conf") == "$xps13_legacy_block" ]]; then
    rm -f -- "$xps13_managed_conf" || return 3
    return 0
  fi

  begin_line="$(grep -Fnx "$xps13_managed_begin" "$xps13_managed_conf" || true)"
  end_line="$(grep -Fnx "$xps13_managed_end" "$xps13_managed_conf" || true)"
  if [[ -z $begin_line && -z $end_line ]]; then
    return 1
  fi
  if [[ ! $begin_line =~ ^[0-9]+: || ! $end_line =~ ^[0-9]+: ||
        $begin_line == *$'\n'* || $end_line == *$'\n'* ||
        ${begin_line%%:*} -ge ${end_line%%:*} ]]; then
    echo "Refusing to alter malformed managed markers in $xps13_managed_conf" >&2
    return 2
  fi

  tmp="$(mktemp "${xps13_managed_conf}.XXXXXX")" || return 3
  if ! awk -v begin="$xps13_managed_begin" -v end="$xps13_managed_end" '
    $0 == begin { managed = 1; next }
    $0 == end { managed = 0; next }
    !managed { print }
  ' "$xps13_managed_conf" >"$tmp"; then
    rm -f -- "$tmp"
    return 3
  fi

  if grep -Eq '[^[:space:]]' "$tmp"; then
    if ! chmod --reference="$xps13_managed_conf" "$tmp" ||
      ! chown --reference="$xps13_managed_conf" "$tmp" ||
      ! mv -f -- "$tmp" "$xps13_managed_conf"; then
      rm -f -- "$tmp"
      return 3
    fi
  else
    rm -f -- "$tmp"
    rm -f -- "$xps13_managed_conf" || return 3
  fi
  return 0
}

xps13_managed_override_present() {
  [[ -f $xps13_managed_conf ]] || return 1
  [[ $(<"$xps13_managed_conf") == "$xps13_legacy_block" ]] && return 0
  grep -Fxq "$xps13_managed_begin" "$xps13_managed_conf" &&
    grep -Fxq "$xps13_managed_end" "$xps13_managed_conf"
}

xps13_kernel_hook_is_managed() {
  [[ -f $xps13_kernel_hook ]] &&
    [[ $(<"$xps13_kernel_hook") == "$xps13_kernel_hook_contents" ]]
}

xps13_ensure_kernel_hook() {
  local tmp
  if [[ -f $xps13_kernel_hook ]]; then
    if xps13_kernel_hook_is_managed; then
      return 1
    fi
    echo "Refusing to replace existing kernel hook: $xps13_kernel_hook" >&2
    return 2
  fi

  mkdir -p "$(dirname "$xps13_kernel_hook")" || return 3
  tmp="$(mktemp "${xps13_kernel_hook}.XXXXXX")" || return 3
  if ! printf '%s\n' "$xps13_kernel_hook_contents" >"$tmp" ||
    ! chmod 0644 "$tmp" || ! mv -f -- "$tmp" "$xps13_kernel_hook"; then
    rm -f -- "$tmp"
    return 3
  fi
  return 0
}

xps13_remove_kernel_hook() {
  xps13_kernel_hook_is_managed || return 1
  rm -f -- "$xps13_kernel_hook" || return 3
}

xps13_ensure_managed_override() {
  local quirk quirk_output tmp
  local -a quirks=()

  quirk_output="$(xps13_effective_quirks)" || return 3
  if [[ -n $quirk_output ]]; then
    mapfile -t quirks <<<"$quirk_output"
  fi
  for quirk in "${quirks[@]}"; do
    if [[ $quirk != "65536" ]]; then
      echo "Refusing to replace an existing snd_soc_sof_sdw quirk=$quirk override" >&2
      return 2
    fi
  done

  ((${#quirks[@]} == 0)) || return 1

  mkdir -p "$(dirname "$xps13_managed_conf")" || return 3
  tmp="$(mktemp "${xps13_managed_conf}.XXXXXX")" || return 3
  if [[ -s $xps13_managed_conf ]]; then
    if ! cat "$xps13_managed_conf" >"$tmp" ||
      ! printf '\n%s\n' "$xps13_managed_block" >>"$tmp" ||
      ! chmod --reference="$xps13_managed_conf" "$tmp" ||
      ! chown --reference="$xps13_managed_conf" "$tmp"; then
      rm -f -- "$tmp"
      return 3
    fi
  else
    if ! printf '%s\n' "$xps13_managed_block" >"$tmp" || ! chmod 0644 "$tmp"; then
      rm -f -- "$tmp"
      return 3
    fi
  fi
  mv -f -- "$tmp" "$xps13_managed_conf" || {
    rm -f -- "$tmp"
    return 3
  }
  return 0
}

xps13_rebuild_boot_images() {
  if command -v limine-mkinitcpio >/dev/null; then
    limine-mkinitcpio
  else
    mkinitcpio -P
  fi
}

xps13_sidecar_apply() {
  local mode="$1" active="" ensure_status hook_status remove_status
  local override_changed=0 override_owned=0 hook_owned=0

  xps13_sidecar_hardware_matches || return 0
  ((EUID == 0)) || {
    echo "Dell XPS 13 sidecar setup must run as root" >&2
    return 1
  }

  mkdir -p "$(dirname "$xps13_lock")" || return 1
  (
    exec {xps13_lock_fd}>"$xps13_lock" || return 1
    flock "$xps13_lock_fd" || return 1

    if xps13_all_installed_kernels_are_native; then
      # Record cleanup intent before altering the override. This covers an
      # existing hand-installed Omarchy legacy file that predates the pacman
      # hook: a failed rebuild remains visible and retryable on the next run.
      if xps13_managed_override_present && [[ ! -e $xps13_cleanup_pending ]]; then
        install -Dm644 /dev/null "$xps13_cleanup_pending" || return
      fi
      if xps13_remove_managed_override; then
        override_changed=1
      else
        remove_status=$?
        ((remove_status == 1)) || return "$remove_status"
      fi
      if xps13_kernel_hook_is_managed; then
        hook_owned=1
      fi

      if ((override_changed || hook_owned)) || [[ -e $xps13_cleanup_pending ]]; then
        # Keep the hook/pending marker until the rebuild succeeds. This also
        # covers a later manual omarchy-apply-hardware run, which operates on
        # existing boot images rather than a fresh install's not-yet-built UKI.
        xps13_rebuild_boot_images || return
        if ((hook_owned)); then
          xps13_remove_kernel_hook || return
        fi
        rm -f -- "$xps13_repair_marker" || return
        rm -f -- "$xps13_cleanup_pending" || return
        [[ $mode == "migrate" ]] && return 10
      fi
      return 0
    fi

    if xps13_ensure_managed_override; then
      override_changed=1
      override_owned=1
    else
      ensure_status=$?
      if ((ensure_status == 2)) && [[ $mode != "migrate" ]]; then
        return 0
      fi
      ((ensure_status == 1)) || return "$ensure_status"
      if xps13_managed_override_present; then
        override_owned=1
      fi
    fi

    if ((override_owned)); then
      if xps13_ensure_kernel_hook; then
        :
      else
        hook_status=$?
        if ((hook_status == 2)); then
          if ((override_changed)); then
            if xps13_remove_managed_override; then
              :
            else
              remove_status=$?
              ((remove_status == 1 || remove_status == 2)) || return "$remove_status"
            fi
          fi
          if [[ $mode != "migrate" ]]; then
            return 0
          fi
        fi
        ((hook_status == 1)) || return "$hook_status"
      fi
    fi

    [[ $mode == "migrate" ]] || return 0

    active="$(cat "$xps13_active_quirk" 2>/dev/null || true)"
    if [[ $active != "65536" ]]; then
      if ((override_changed)) || [[ ! -e $xps13_repair_marker ]]; then
        xps13_rebuild_boot_images || return
        install -Dm644 /dev/null "$xps13_repair_marker" || return
      fi
      return 10
    fi
  )
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  set -euo pipefail
  case "${1:-}" in
    --migrate) xps13_sidecar_apply migrate ;;
    --kernel-updated) xps13_sidecar_apply kernel-update ;;
    *)
      echo "Usage: $0 <--migrate|--kernel-updated>" >&2
      exit 2
      ;;
  esac
else
  xps13_sidecar_apply install
fi
