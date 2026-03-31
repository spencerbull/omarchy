echo "Keep PSR enabled while disabling Panel Replay on Dell XPS OLED"

if omarchy-cmd-present limine-update \
  && omarchy-hw-match "XPS" \
  && omarchy-hw-intel-ptl \
  && test "$(od -An -tx1 -j8 -N2 /sys/class/drm/card*-eDP-*/edid 2>/dev/null | tr -d ' \n')" = "30e4"; then

  CMDLINE='KERNEL_CMDLINE[default]+=" xe.enable_panel_replay=0"'

  sudo mkdir -p /etc/limine-entry-tool.d
  cat <<EOF | sudo tee /etc/limine-entry-tool.d/dell-xps-ptl-display.conf >/dev/null
# Fix Dell XPS OLED display issues by disabling Xe Panel Replay only
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
