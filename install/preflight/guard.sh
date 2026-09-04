abort() {
  echo -e "\e[31mOmarchy install requires: $1\e[0m"
  echo
  gum confirm "Proceed anyway on your own accord and without assistance?" || exit 1
}

# Must be an Arch distro
if [[ ! -f /etc/arch-release ]]; then
  abort "Vanilla Arch"
fi

# Must not be an Arch derivative distro
for marker in /etc/cachyos-release /etc/eos-release /etc/garuda-release /etc/manjaro-release; do
  if [[ -f $marker ]]; then
    abort "Vanilla Arch"
  fi
done

# Must not be running as root
if (( EUID == 0 )); then
  abort "Running as root (not user)"
fi

# AArch64 enablement is currently authorized only by the complete development
# image. Public Omarchy repositories do not provide this package closure.
if [[ $(uname -m) != "x86_64" ]]; then
  if [[ $(uname -m) != aarch64 || ${OMARCHY_ARM_IMAGE_INSTALL:-} != 1 || ${OMARCHY_ARM_PLATFORM:-} != "gb10" && ${OMARCHY_ARM_PLATFORM:-} != "n1x" || -n ${OMARCHY_ONLINE_INSTALL:-} || ${OMARCHY_CHROOT_INSTALL:-} != 1 ]]; then
    echo -e "\e[31mAArch64 requires the complete authorized development installer image; direct and online installs are not available.\e[0m"
    exit 1
  fi
fi

# Must have secure boot disabled
if bootctl status 2>/dev/null | grep -q 'Secure Boot: enabled'; then
  abort "Secure Boot disabled"
fi

# Must not have Gnome or KDE already install
if pacman -Qe gnome-shell &>/dev/null || pacman -Qe plasma-desktop &>/dev/null; then
  abort "Fresh + Vanilla Arch"
fi

# Must have limine installed
command -v limine &>/dev/null || abort "Limine bootloader"

# Must have btrfs root filesystem
[[ $(findmnt -n -o FSTYPE /) = "btrfs" ]] || abort "Btrfs root filesystem" 

# Cleared all guards
echo "Guards: OK"
