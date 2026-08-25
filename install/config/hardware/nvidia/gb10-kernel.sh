# Install the NVIDIA GB10 kernel before configuring its DKMS driver.
if [[ $(uname -m) == aarch64 ]]; then
  if ! omarchy-hw-nvidia-gb10; then
    echo "Error: exact GB10 hardware evidence disappeared before the kernel transition" >&2
    return 1
  fi
  echo "Detected NVIDIA GB10, installing GB10 kernel..."

  if ! omarchy-pkg-add linux-gb10 linux-gb10-headers; then
    echo "Error: failed to install the GB10 kernel transaction" >&2
    return 1
  fi
  if ! pacman -Q linux-gb10 linux-gb10-headers >/dev/null; then
    echo "Error: the GB10 kernel and headers are not both installed" >&2
    return 1
  fi

  # Remove the generic kernel only after the complete GB10 pair is proven.
  if ! omarchy-pkg-drop linux linux-headers; then
    echo "Error: failed to remove the generic kernel after installing GB10" >&2
    return 1
  fi
  if pacman -Q linux >/dev/null 2>&1 || pacman -Q linux-headers >/dev/null 2>&1; then
    echo "Error: generic kernel packages remain after the GB10 transition" >&2
    return 1
  fi

  sudo mkdir -p /etc/limine-entry-tool.d || return 1
  if ! cat <<EOF | sudo tee /etc/limine-entry-tool.d/nvidia-gb10.conf >/dev/null
# Only show the GB10 kernel first in the boot menu on NVIDIA GB10 systems
BOOT_ORDER="linux-gb10*, *fallback, Snapshots"
EOF
  then
    echo "Error: failed to configure the GB10 Limine boot order" >&2
    return 1
  fi
fi
