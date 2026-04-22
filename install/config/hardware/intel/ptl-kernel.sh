# Install Panther Lake kernel for Intel Panther Lake systems.
# The linux-ptl kernel includes audio driver patches not yet in mainline.
# Enable FRED on Panther Lake when supported by the CPU and kernel.

if omarchy-hw-intel-ptl; then
  echo "Detected Intel Panther Lake, installing PTL kernel and enabling FRED..."

  CMDLINE='KERNEL_CMDLINE[default]+=" fred=on"'

  omarchy-pkg-add linux-ptl linux-ptl-headers
  sudo pacman -Rdd --noconfirm linux linux-headers 2>/dev/null || true

  sudo mkdir -p /etc/limine-entry-tool.d
  cat <<EOF | sudo tee /etc/limine-entry-tool.d/intel-panther-lake.conf >/dev/null
# Only show Panther Lake kernel in boot menu
BOOT_ORDER="linux-ptl*, *fallback, Snapshots"
# Enable Intel FRED on Panther Lake when supported by the kernel and CPU
$CMDLINE
EOF

  if [[ -f /etc/default/limine ]] && ! grep -q 'fred=on' /etc/default/limine; then
    echo "$CMDLINE" | sudo tee -a /etc/default/limine >/dev/null
  fi
fi
