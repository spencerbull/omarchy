# Add friendly labels for Dell XPS Panther Lake SoundWire audio endpoints.

if omarchy-hw-match "XPS" && omarchy-hw-intel-ptl; then
  omarchy-pkg-add omarchy-xps-panther-lake-audio
fi
