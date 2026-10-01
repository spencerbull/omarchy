# Install the experimental NVIDIA N1x kernel before configuring its DKMS
# driver. The complete development image is the authorization boundary while
# pre-release N1x DMI and PCI identities are still changing.
if [[ $(uname -m) == aarch64 && ${OMARCHY_ARM_PLATFORM:-} == "n1x" ]]; then
  if [[ ${OMARCHY_ARM_IMAGE_INSTALL:-} != 1 ]]; then
    echo "Error: ARM image authorization disappeared before the N1x kernel transition" >&2
    return 1
  fi
  echo "Authorized AArch64 N1x image, installing linux-n1x kernel..."

  if ! omarchy-pkg-add linux-n1x linux-n1x-headers; then
    echo "Error: failed to install the N1x kernel transaction" >&2
    return 1
  fi
  if ! pacman -Q linux-n1x linux-n1x-headers >/dev/null; then
    echo "Error: the N1x kernel and headers are not both installed" >&2
    return 1
  fi

  # Remove the generic kernel only after the complete N1x pair is proven.
  if ! omarchy-pkg-drop linux linux-headers; then
    echo "Error: failed to remove the generic kernel after installing N1x" >&2
    return 1
  fi
  if pacman -Q linux >/dev/null 2>&1 || pacman -Q linux-headers >/dev/null 2>&1; then
    echo "Error: generic kernel packages remain after the N1x transition" >&2
    return 1
  fi

  # Keep both the internal I2C-HID keyboard path and an external USB keyboard
  # available before the real root is mounted. Autodetect alone is unreliable
  # while the target initramfs is generated from the live installer.
  if ! cat <<'EOF' | sudo tee /etc/mkinitcpio.conf.d/n1x-input.conf >/dev/null
MODULES+=(i2c_tegra i2c_hid i2c_hid_acpi hid_generic hid_multitouch usbhid)
EOF
  then
    echo "Error: failed to configure the N1x early keyboard modules" >&2
    return 1
  fi

  sudo mkdir -p /etc/limine-entry-tool.d || return 1
  if ! cat <<'EOF' | sudo tee /etc/limine-entry-tool.d/nvidia-n1x.conf >/dev/null
# Put the diagnostic rescue entry first until the exact N1x GPU identity and
# driver behavior have been captured over SSH.
BOOT_ORDER="linux-n1x-rescue, linux-n1x, *fallback, *, Snapshots"
EOF
  then
    echo "Error: failed to configure the N1x Limine boot order" >&2
    return 1
  fi
fi
