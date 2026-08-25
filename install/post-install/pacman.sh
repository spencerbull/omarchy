# Configure pacman
if [[ $(uname -m) == aarch64 ]]; then
  sudo cp -f ~/.local/share/omarchy/default/pacman/pacman-aarch64.conf /etc/pacman.conf || return 1
  sudo cp -f ~/.local/share/omarchy/default/pacman/mirrorlist-aarch64 /etc/pacman.d/mirrorlist || return 1
else
  sudo cp -f ~/.local/share/omarchy/default/pacman/pacman-${OMARCHY_MIRROR:-stable}.conf /etc/pacman.conf
  sudo cp -f ~/.local/share/omarchy/default/pacman/mirrorlist-${OMARCHY_MIRROR:-stable} /etc/pacman.d/mirrorlist
fi

if lspci -nn | grep -q "106b:180[12]"; then
  cat <<EOF | sudo tee -a /etc/pacman.conf >/dev/null

[arch-mact2]
Server = https://github.com/NoaHimesaka1873/arch-mact2-mirror/releases/download/release
SigLevel = Never
EOF
fi
