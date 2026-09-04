if [[ $(uname -m) != aarch64 || ${OMARCHY_ARM_PLATFORM:-} != "n1x" ]]; then
  return
fi
if [[ ${OMARCHY_ARM_IMAGE_INSTALL:-} != 1 ]]; then
  echo "Error: ARM image authorization disappeared before N1x recovery setup" >&2
  return 1
fi

if ! omarchy-pkg-add openssh pciutils; then
  echo "Error: failed to install the N1x recovery packages" >&2
  return 1
fi

install -d -m 0700 "$HOME/.ssh"
if ! grep -Fqx 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ4eMMpL8q81NSRMKSBP+x8WGw07QxYlvLpccQnZNh7C sbull-n1x-recovery' "$HOME/.ssh/authorized_keys" 2>/dev/null; then
  echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ4eMMpL8q81NSRMKSBP+x8WGw07QxYlvLpccQnZNh7C sbull-n1x-recovery' >>"$HOME/.ssh/authorized_keys"
fi
chmod 0600 "$HOME/.ssh/authorized_keys"

sudo install -d -m0755 /etc/ssh/sshd_config.d
sudo tee /etc/ssh/sshd_config.d/20-omarchy-n1x-recovery.conf <<'EOF' >/dev/null
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
EOF

sudo install -Dm0755 "$OMARCHY_INSTALL/config/hardware/nvidia/n1x-probe" /usr/local/sbin/omarchy-n1x-probe
sudo tee /etc/systemd/system/omarchy-n1x-probe.service <<'EOF' >/dev/null
[Unit]
Description=Capture N1x bring-up hardware and boot evidence
After=local-fs.target network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/omarchy-n1x-probe
StandardOutput=journal+console
StandardError=journal+console
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

chrootable_systemctl_enable sshd.service
chrootable_systemctl_enable systemd-networkd.service
chrootable_systemctl_enable systemd-resolved.service
chrootable_systemctl_enable omarchy-n1x-probe.service

# Preserve SSH access if Omarchy's first-run firewall is completed later.
if command -v ufw >/dev/null 2>&1; then
  sudo ufw allow 22/tcp >/dev/null
fi
