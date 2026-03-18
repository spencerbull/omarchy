echo "Fix Panther Lake audio: replace SOF blacklist with proper module autoload"

if lspci | grep -iE 'vga|3d|display' | grep -qi 'panther lake'; then
  sudo rm -f /etc/modprobe.d/blacklist-audio.conf

  sudo tee /etc/modules-load.d/panther-lake-audio.conf << 'EOF'
# Panther Lake (Dell XPS 2026) audio - SOF + Cirrus codecs
# snd_hda_intel and snd_sof_pci_intel_ptl both match PCI 8086:e428 and
# hda wins the boot race without handing off to SOF automatically.
snd_sof_pci_intel_ptl
snd_soc_cs42l43_sdw
snd_soc_cs35l56_sdw
EOF
fi
