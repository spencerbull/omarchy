echo "Add friendly audio labels for Dell XPS Panther Lake"

if omarchy-hw-match "XPS" && omarchy-hw-intel-ptl; then
  omarchy-pkg-add omarchy-xps-panther-lake-audio

  mkdir -p ~/.config/wiremix
  if [[ ! -f ~/.config/wiremix/wiremix.toml ]]; then
    cp -f "$OMARCHY_PATH/config/wiremix/wiremix.toml" ~/.config/wiremix/
  fi

  if ! grep -q "node:alsa.driver_name.*snd_soc_sof_sdw" ~/.config/wiremix/wiremix.toml; then
    cat <<'EOF' >> ~/.config/wiremix/wiremix.toml

[[names.overrides]]
types = [ "endpoint" ]
matches = [ { "node:alsa.driver_name" = "snd_soc_sof_sdw", "node:alsa.long_card_name" = "~DellInc\\.-XPS.*" } ]
templates = [ "{node:node.description}" ]
EOF
  fi

  systemctl --user restart wireplumber.service 2>/dev/null || true
fi
