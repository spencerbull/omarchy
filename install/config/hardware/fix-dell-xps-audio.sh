# Fix audio on Dell XPS 2026 (Panther Lake) by blacklisting SOF audio modules
# that conflict with standard HDA drivers. This turns off audio, but allows boot.
# This is meant to be removed as soon as its fixed upstream.
#
# Skip if linux-mainline is installed — it includes the proper kernel config
# options (CONFIG_SND_SOC_SOF_NOVALAKE, etc.) that resolve the conflict.

if omarchy-pkg-present linux-mainline; then
  return 0 2>/dev/null || exit 0
fi

if lspci | grep -iE 'vga|3d|display' | grep -qi 'panther lake'; then
  sudo tee /etc/modprobe.d/blacklist-audio.conf << 'EOF'
blacklist snd_sof_pci_intel_ptl
blacklist snd_sof_pci_intel_lnl
blacklist snd_sof_pci_intel_mtl
blacklist snd_sof_intel_hda_generic
blacklist snd_sof_intel_hda_common
blacklist snd_sof_intel_hda
blacklist snd_sof_pci
blacklist snd_sof
blacklist soundwire_intel
blacklist snd_soc_cs35l56_sdw
blacklist snd_soc_cs35l56
blacklist snd_soc_skl_hda_dsp
EOF
fi
