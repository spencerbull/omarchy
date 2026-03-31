echo "Keep PSR enabled while disabling Panel Replay on Dell XPS 14 OLED"

if omarchy-cmd-present limine-update \
  && omarchy-hw-xps-14-oled \
  && omarchy-hw-intel-ptl; then

  CMDLINE='KERNEL_CMDLINE[default]+=" xe.enable_panel_replay=0"'

  sudo mkdir -p /etc/limine-entry-tool.d
  cat <<EOF | sudo tee /etc/limine-entry-tool.d/dell-xps-ptl-display.conf >/dev/null
# Fix Dell XPS 14 OLED display issues by disabling Xe Panel Replay only
$CMDLINE
EOF

  if [[ -f /etc/default/limine ]]; then
    sudo perl -0pi -e 's/ xe\.enable_psr=0 xe\.enable_panel_replay=0 xe\.enable_fbc=0 xe\.enable_dc=0/ xe.enable_panel_replay=0/g' /etc/default/limine

    if ! sudo grep -q 'xe.enable_panel_replay=0' /etc/default/limine; then
      echo "$CMDLINE" | sudo tee -a /etc/default/limine >/dev/null
    fi
  fi

  sudo limine-update
fi
