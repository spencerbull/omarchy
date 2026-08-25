if [[ $(uname -m) == aarch64 ]] && ! omarchy-hw-nvidia-gb10; then
  echo "Error: exact GB10 hardware evidence disappeared before Limine finalization" >&2
  return 1
fi

if command -v limine &>/dev/null; then
  sudo tee /etc/mkinitcpio.conf.d/omarchy_hooks.conf <<EOF >/dev/null
HOOKS=(base udev plymouth keyboard autodetect microcode modconf kms keymap consolefont block encrypt filesystems fsck btrfs-overlayfs)
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

  # Only snapshot root — /home is user data; rolling it back loses user work
  if ! sudo snapper list-configs 2>/dev/null | grep -q "root"; then
    sudo snapper -c root create-config /
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

if [[ $(uname -m) == aarch64 ]]; then
  if ! omarchy-hw-nvidia-gb10; then
    echo "Error: exact GB10 hardware evidence disappeared before Limine validation" >&2
    return 1
  fi
  for required_limine_binary in \
    /boot/EFI/limine/limine_aa64.efi \
    /boot/EFI/BOOT/BOOTAA64.EFI; do
    if [[ ! -f $required_limine_binary ]]; then
      echo "Error: GB10 Limine deployment did not create $required_limine_binary" >&2
      exit 1
    fi
  done
fi

if [[ -n $EFI ]] && efibootmgr &>/dev/null; then
  replacement_entry_ready=true
  if [[ $(uname -m) == aarch64 ]]; then
    if ! omarchy-hw-nvidia-gb10; then
      echo "Error: exact GB10 hardware evidence disappeared before NVRAM validation" >&2
      return 1
    fi
    if ! efibootmgr | grep -Fiq '\EFI\limine\limine_aa64.efi'; then
      replacement_entry_ready=false
      echo "Warning: keeping the Archinstall Limine NVRAM entry because the GB10 replacement entry was not verified." >&2
    fi
  fi

  if [[ $replacement_entry_ready == true ]]; then
    # Remove the Archinstall-created entry only after its replacement is proven.
    while IFS= read -r bootnum; do
      sudo efibootmgr -b "$bootnum" -B >/dev/null 2>&1
    done < <(efibootmgr | grep -E "^Boot[0-9]{4}\*? Arch Linux Limine" | sed 's/^Boot\([0-9]\{4\}\).*/\1/')
  fi
fi
