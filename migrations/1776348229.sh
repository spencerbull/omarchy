echo "Enable Intel FRED on Panther Lake systems"

if omarchy-hw-intel-ptl && [[ -f /etc/default/limine ]]; then
  CMDLINE='KERNEL_CMDLINE[default]+=" fred=on"'
  DROP_IN="/etc/limine-entry-tool.d/intel-panther-lake.conf"
  UPDATED=false

  sudo mkdir -p /etc/limine-entry-tool.d

  if [[ ! -f $DROP_IN ]] || ! grep -q 'fred=on' "$DROP_IN"; then
    cat <<EOF | sudo tee "$DROP_IN" >/dev/null
# Only show Panther Lake kernel in boot menu
BOOT_ORDER="linux-ptl*, *fallback, Snapshots"
# Enable Intel FRED on Panther Lake when supported by the kernel and CPU
$CMDLINE
EOF
    UPDATED=true
  fi

  if ! grep -q 'fred=on' /etc/default/limine; then
    echo "$CMDLINE" | sudo tee -a /etc/default/limine >/dev/null
    UPDATED=true
  fi

  if [[ $UPDATED == "true" ]]; then
    sudo limine-mkinitcpio
  fi
fi
