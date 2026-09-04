if [[ $(uname -m) == aarch64 && ${OMARCHY_ARM_IMAGE_INSTALL:-} != 1 ]]; then
  echo "Error: ARM image authorization disappeared before Limine finalization" >&2
  return 1
fi

if command -v limine &>/dev/null; then
  mkinitcpio_hooks="base udev plymouth keyboard autodetect microcode modconf kms keymap consolefont block encrypt filesystems fsck btrfs-overlayfs"
  if [[ $(uname -m) == aarch64 ]]; then
    mkinitcpio_hooks=${mkinitcpio_hooks/ plymouth/}
  fi
  sudo tee /etc/mkinitcpio.conf.d/omarchy_hooks.conf <<EOF >/dev/null
HOOKS=($mkinitcpio_hooks)
EOF
  sudo tee /etc/mkinitcpio.conf.d/thunderbolt_module.conf <<EOF >/dev/null
MODULES+=(thunderbolt)
EOF

  # Detect boot mode
  [[ -d /sys/firmware/efi ]] && EFI=true

  # Find config location
  if [[ -f /boot/EFI/arch-limine/limine.conf ]]; then
    limine_config="/boot/EFI/arch-limine/limine.conf"
  elif [[ -f /boot/EFI/BOOT/limine.conf ]]; then
    limine_config="/boot/EFI/BOOT/limine.conf"
  elif [[ -f /boot/EFI/limine/limine.conf ]]; then
    limine_config="/boot/EFI/limine/limine.conf"
  elif [[ -f /boot/limine/limine.conf ]]; then
    limine_config="/boot/limine/limine.conf"
  elif [[ -f /boot/limine.conf ]]; then
    limine_config="/boot/limine.conf"
  else
    echo "Error: Limine config not found" >&2
    exit 1
  fi

  CMDLINE=$(grep "^[[:space:]]*cmdline:" "$limine_config" | head -1 | sed 's/^[[:space:]]*cmdline:[[:space:]]*//')

  # Write /etc/default/limine *before* installing limine-mkinitcpio-hook, whose
  # post-transaction deploy hook runs limine-install and reads this file. Without
  # it, ESP_PATH falls back to bootctl, which in a chroot prints a warning that
  # gets captured as the path and trips a spurious "invalid ESP" error.
  sudo cp $OMARCHY_PATH/default/limine/default.conf /etc/default/limine
  sudo sed -i "s|@@CMDLINE@@|$CMDLINE|g" /etc/default/limine

  # Plymouth crashes in strcmp() during early boot on the current AArch64
  # userspace. The busybox mkinitcpio hook starts plymouthd unconditionally, so
  # omit it above and retain disablehooks as a runtime safeguard if another
  # config adds it back.
  #
  # limine-entry-tool prepends "+=" lines instead of appending them, so a later
  # verbose line cannot override the quiet defaults: the first N1x install
  # produced "loglevel=7 ... quiet splash loglevel=0" and booted silently.
  # Remove the quiet line outright on AArch64 instead of trying to out-order it.
  #
  # The N1x kernel is built with CONFIG_CMDLINE="console=ttyAMA0" and ACPI SPCR
  # support, so without an explicit console the LUKS passphrase prompt and any
  # initramfs emergency shell land on a serial UART while the panel stays black.
  # Pin the console to the panel and stop the kernel from adopting the firmware
  # serial console. This must precede the Limine package hook, which reads
  # /etc/default/limine while generating the UKI and boot entry.
  if [[ $(uname -m) == aarch64 ]]; then
    sudo sed -i '/^KERNEL_CMDLINE\[default\]+=" quiet splash loglevel=0 /d' /etc/default/limine
    if grep -Eq '(^|[[:space:]"])quiet([[:space:]"]|$)' /etc/default/limine; then
      echo "Error: failed to remove the quiet AArch64 Limine defaults" >&2
      return 1
    fi
    echo 'KERNEL_CMDLINE[default]+=" console=tty0 acpi=nospcr disablehooks=plymouth plymouth.enable=0 loglevel=7 ignore_loglevel systemd.show_status=1 rd.udev.log_level=info vt.global_cursor_default=1"' | sudo tee -a /etc/default/limine >/dev/null
  fi
  if [[ $(uname -m) == aarch64 && ${OMARCHY_ARM_PLATFORM:-} == "n1x" ]]; then
    N1X_RESCUE_CMDLINE="$CMDLINE omarchy.n1x_recovery=1 acpi=nospcr disablehooks=plymouth plymouth.enable=0 nomodeset module_blacklist=nvidia,nvidia_drm,nvidia_modeset,nvidia_uvm,nvidia_peermem,nouveau modprobe.blacklist=nvidia,nvidia_drm,nvidia_modeset,nvidia_uvm,nvidia_peermem,nouveau nvidia_drm.modeset=0 systemd.unit=multi-user.target console=tty0 fbcon=map:0 earlycon loglevel=7 ignore_loglevel systemd.show_status=1 systemd.log_target=console udev.log_level=debug vt.global_cursor_default=1"
    # Limine hands an entry's "cmdline:" to the UKI as EFI load options, and
    # systemd-stub prefers those over the embedded .cmdline section. The first
    # N1x install therefore booted the rescue UKI with the normal command line.
    # Give the rescue entry its own line through the tool's per-kernel key.
    echo "KERNEL_CMDLINE[linux-n1x-rescue]=\"$N1X_RESCUE_CMDLINE\"" | sudo tee -a /etc/default/limine >/dev/null
  fi

  # Append any drop-in kernel cmdline configs (from hardware fix scripts, etc.)
  for dropin in /etc/limine-entry-tool.d/*.conf; do
    [ -f "$dropin" ] && cat "$dropin" | sudo tee -a /etc/default/limine >/dev/null
  done

  # UKI and EFI fallback are EFI only
  if [[ -z $EFI ]]; then
    sudo sed -i '/^ENABLE_UKI=/d; /^ENABLE_LIMINE_FALLBACK=/d' /etc/default/limine
  fi

  # Remove the original config file if it's not /boot/limine.conf, so the deploy
  # hook doesn't see conflicting configs on the same ESP.
  if [[ $limine_config != "/boot/limine.conf" ]] && [[ -f $limine_config ]]; then
    sudo rm "$limine_config"
  fi

  # We overwrite the whole thing knowing the limine-update will add the entries for us
  sudo cp $OMARCHY_PATH/default/limine/limine.conf /boot/limine.conf

  sudo pacman -S --noconfirm --needed limine-snapper-sync limine-mkinitcpio-hook

  # The hook's generic fallback disables autodetect and can pull thousands of
  # unrelated AArch64 modules into a UKI. Build a compact rescue UKI from the
  # normal hardware-selected initramfs instead, with NVIDIA disabled and a
  # verbose multi-user target for console and SSH diagnosis.
  if [[ $(uname -m) == aarch64 && ${OMARCHY_ARM_PLATFORM:-} == "n1x" ]]; then
    mapfile -t n1x_pkgbase_files < <(grep -lFx linux-n1x /usr/lib/modules/*/pkgbase 2>/dev/null || true)
    if (( ${#n1x_pkgbase_files[@]} != 1 )); then
      echo "Error: expected one installed linux-n1x module tree, found ${#n1x_pkgbase_files[@]}" >&2
      exit 1
    fi

    n1x_kernel_version=${n1x_pkgbase_files[0]#/usr/lib/modules/}
    n1x_kernel_version=${n1x_kernel_version%/pkgbase}
    n1x_rescue_cmdline=/tmp/omarchy-n1x-rescue-cmdline
    n1x_rescue_uki=/tmp/omarchy-linux-n1x-rescue.efi
    printf '%s\n' "$N1X_RESCUE_CMDLINE" | sudo tee "$n1x_rescue_cmdline" >/dev/null

    if ! sudo mkinitcpio --kernel "$n1x_kernel_version" --cmdline "$n1x_rescue_cmdline" --uki "$n1x_rescue_uki"; then
      sudo rm -f "$n1x_rescue_cmdline" "$n1x_rescue_uki"
      echo "Error: failed to build the compact N1x rescue UKI" >&2
      exit 1
    fi
    if ! sudo limine-entry-tool --add-uki linux-n1x-rescue "$n1x_rescue_uki" \
      --comment "N1x SSH recovery (graphics disabled)" --overwrite --quiet --no-mutex --no-hooks; then
      sudo rm -f "$n1x_rescue_cmdline" "$n1x_rescue_uki"
      echo "Error: failed to install the compact N1x rescue UKI" >&2
      exit 1
    fi
    sudo rm -f "$n1x_rescue_cmdline" "$n1x_rescue_uki"
  fi

  # Only snapshot root — /home is user data; rolling it back loses user work.
  # The installer runs before snapperd is available in the target session, so
  # use Snapper's direct backend instead of aborting on a D-Bus ServiceUnknown.
  if ! sudo snapper --no-dbus list-configs 2>/dev/null | grep -q "root"; then
    sudo snapper --no-dbus -c root create-config /
  fi
  sudo cp $OMARCHY_PATH/default/snapper/root /etc/snapper/configs/root

  # Disable btrfs quotas — full qgroup accounting is a major performance drag
  sudo btrfs quota disable / 2>/dev/null || true

  chrootable_systemctl_enable limine-snapper-sync.service
fi

echo "Re-enabling mkinitcpio hooks..."

# Restore the specific mkinitcpio pacman hooks
if [[ -f /usr/share/libalpm/hooks/90-mkinitcpio-install.hook.disabled ]]; then
  sudo mv /usr/share/libalpm/hooks/90-mkinitcpio-install.hook.disabled /usr/share/libalpm/hooks/90-mkinitcpio-install.hook
fi

if [[ -f /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook.disabled ]]; then
  sudo mv /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook.disabled /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook
fi

echo "mkinitcpio hooks re-enabled"

# Installing limine-mkinitcpio-hook above already triggered a full UKI rebuild
# (via 80-limine-efi-deploy.hook + 90-mkinitcpio-install.hook), which writes the
# boot entries into /boot/limine.conf. Only fall back to limine-update if those
# hooks didn't run for some reason — running it unconditionally rebuilds every
# UKI a second time.
if ! grep -q "^/+" /boot/limine.conf; then
  sudo limine-update
fi

if ! grep -q "^/+" /boot/limine.conf; then
  echo "Error: failed to add boot entries to /boot/limine.conf" >&2
  exit 1
fi

if [[ $(uname -m) == aarch64 && ${OMARCHY_ARM_PLATFORM:-} == "n1x" ]] && ! grep -Fq 'linux-n1x-rescue' /boot/limine.conf; then
  echo "Error: failed to add the N1x rescue entry to /boot/limine.conf" >&2
  exit 1
fi

# Print the cmdline Limine will pass to the rescue UKI. Entry headers start
# with one or more slashes; everything until the next header belongs to the
# rescue entry.
n1x_rescue_entry_cmdline() {
  awk '
    /^[[:space:]]*\/+[^\/]/ { in_rescue = ($0 ~ /^[[:space:]]*\/\/linux-n1x-rescue[[:space:]]*$/) }
    in_rescue && /^[[:space:]]*cmdline:/ { sub(/^[[:space:]]*cmdline:[[:space:]]*/, ""); print; exit }
  ' /boot/limine.conf
}

if [[ $(uname -m) == aarch64 && ${OMARCHY_ARM_PLATFORM:-} == "n1x" ]]; then
  if [[ $(n1x_rescue_entry_cmdline) != "$N1X_RESCUE_CMDLINE" ]]; then
    # The per-kernel key was not honored for the custom UKI entry. Rewrite the
    # rescue cmdline in place so the entry actually boots to the console.
    echo "Warning: rewriting the N1x rescue entry cmdline in /boot/limine.conf" >&2
    awk -v cmdline="$N1X_RESCUE_CMDLINE" '
      /^[[:space:]]*\/+[^\/]/ { in_rescue = ($0 ~ /^[[:space:]]*\/\/linux-n1x-rescue[[:space:]]*$/) }
      in_rescue && /^[[:space:]]*cmdline:/ { match($0, /^[[:space:]]*/); $0 = substr($0, 1, RLENGTH) "cmdline: " cmdline }
      { print }
    ' /boot/limine.conf | sudo tee /boot/limine.conf.n1x >/dev/null
    sudo mv /boot/limine.conf.n1x /boot/limine.conf
  fi
  if [[ $(n1x_rescue_entry_cmdline) != "$N1X_RESCUE_CMDLINE" ]]; then
    echo "Error: the N1x rescue entry does not carry its console cmdline in /boot/limine.conf" >&2
    exit 1
  fi
fi

# Every generated AArch64 entry must boot to the panel and must not be quiet;
# otherwise a LUKS prompt or initramfs failure is an unexplained black screen.
if [[ $(uname -m) == aarch64 ]]; then
  if grep -E '^[[:space:]]*cmdline:' /boot/limine.conf | grep -Eq '(^|[[:space:]])quiet([[:space:]]|$)'; then
    echo "Error: an AArch64 Limine entry still boots quietly" >&2
    exit 1
  fi
  if grep -E '^[[:space:]]*cmdline:' /boot/limine.conf | grep -Evq 'console=tty0'; then
    echo "Error: an AArch64 Limine entry does not pin the console to the panel" >&2
    exit 1
  fi
fi

if [[ $(uname -m) == aarch64 ]]; then
  if [[ ${OMARCHY_ARM_IMAGE_INSTALL:-} != 1 ]]; then
    echo "Error: ARM image authorization disappeared before Limine validation" >&2
    return 1
  fi
  for required_limine_binary in \
    /boot/EFI/limine/limine_aa64.efi \
    /boot/EFI/BOOT/BOOTAA64.EFI; do
    if [[ ! -f $required_limine_binary ]]; then
      echo "Error: AArch64 Limine deployment did not create $required_limine_binary" >&2
      exit 1
    fi
  done
fi

if [[ -n $EFI ]] && efibootmgr &>/dev/null; then
  replacement_entry_ready=true
  if [[ $(uname -m) == aarch64 ]]; then
    if [[ ${OMARCHY_ARM_IMAGE_INSTALL:-} != 1 ]]; then
      echo "Error: ARM image authorization disappeared before NVRAM validation" >&2
      return 1
    fi
    if ! efibootmgr | grep -Fiq '\EFI\limine\limine_aa64.efi'; then
      replacement_entry_ready=false
      echo "Warning: keeping the Archinstall Limine NVRAM entry because the AArch64 replacement entry was not verified." >&2
    fi
  fi

  if [[ $replacement_entry_ready == true ]]; then
    # Remove the Archinstall-created entry only after its replacement is proven.
    while IFS= read -r bootnum; do
      sudo efibootmgr -b "$bootnum" -B >/dev/null 2>&1
    done < <(efibootmgr | grep -E "^Boot[0-9]{4}\*? Arch Linux Limine" | sed 's/^Boot\([0-9]\{4\}\).*/\1/')
  fi
fi
