echo "Enable the Dell XPS 13 sidecar speaker amplifiers"

# The root-owned helper serializes the config/rebuild transaction and checks
# installed kernel modules rather than the live ISO or currently loaded module.
# Exit 10 means the transaction succeeded and a reboot is required.
helper="/usr/share/omarchy/install/hardware/dell-xps13-sidecar-amps.sh"
vendor="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)"
sku="$(cat /sys/class/dmi/id/product_sku 2>/dev/null || true)"

[[ $vendor == "Dell Inc." && $sku == "0E53" ]] || exit 0
[[ -r $helper ]] || {
  echo "Missing Dell XPS 13 sidecar helper: $helper" >&2
  exit 1
}

if sudo bash "$helper" --migrate; then
  :
else
  status=$?
  if ((status == 10)); then
    omarchy-state set reboot-required
  else
    exit "$status"
  fi
fi
