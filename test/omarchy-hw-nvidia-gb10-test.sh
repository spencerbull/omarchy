#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
DETECTOR="$ROOT/bin/omarchy-hw-nvidia-gb10"
FIXTURE=$(mktemp -d)
TEST_DETECTOR="$FIXTURE/omarchy-hw-nvidia-gb10"

# Production detection always reads real uname and /sys. Generate a fixture-only
# copy so the tests can inject evidence without making the installed command
# caller-spoofable.
sed \
  -e 's|machine=$(uname -m)|machine=${OMARCHY_TEST_UNAME:?}|' \
  -e 's|sysfs_root=/sys|sysfs_root=${OMARCHY_TEST_SYSFS_ROOT:?}|' \
  "$DETECTOR" >"$TEST_DETECTOR"
chmod +x "$TEST_DETECTOR"

cleanup() {
  rm -rf "$FIXTURE"
}
trap cleanup EXIT

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

run_detector() {
  local machine=$1

  OMARCHY_TEST_UNAME="$machine" \
    OMARCHY_TEST_SYSFS_ROOT="$FIXTURE" \
    "$TEST_DETECTOR"
}

assert_detected() {
  local description=$1

  run_detector aarch64 || fail "$description"
  pass "$description"
}

assert_not_detected() {
  local description=$1 machine=${2:-aarch64}

  if run_detector "$machine"; then
    fail "$description"
  fi
  pass "$description"
}

write_fixture() {
  local soc_id=$1 vendor=$2 device=$3 subsystem_device=$4
  local pci_device="$FIXTURE/bus/pci/devices/0000:01:00.0"

  rm -rf "$FIXTURE/devices" "$FIXTURE/bus"
  mkdir -p "$FIXTURE/devices/soc0" "$pci_device"
  printf '%s\n' "$soc_id" >"$FIXTURE/devices/soc0/soc_id"
  printf '%s\n' "$vendor" >"$pci_device/vendor"
  printf '%s\n' "$device" >"$pci_device/device"
  printf '%s\n' "$subsystem_device" >"$pci_device/subsystem_device"
}

write_fixture "jep106:0426:8901" "0x10de" "0x2e12" "0x0000"
assert_detected "detects the exact Coleman SoC and PCI tuple"

printf '%s\n' "0x21ec" >"$FIXTURE/bus/pci/devices/0000:01:00.0/subsystem_device"
assert_detected "does not require a specific PCI subsystem device"

assert_not_detected "rejects the Coleman tuple on the wrong architecture" x86_64

write_fixture "jep106:0426:8902" "0x10de" "0x2e12" "0x0000"
assert_not_detected "rejects the wrong SoC ID"

write_fixture "jep106:0426:8901" "0x1234" "0x2e12" "0x0000"
assert_not_detected "rejects the wrong PCI vendor"

write_fixture "jep106:0426:8901" "0x10de" "0x2e13" "0x0000"
assert_not_detected "rejects the wrong PCI device"

rm -rf "$FIXTURE/devices" "$FIXTURE/bus"
assert_not_detected "rejects missing sysfs evidence"

if grep -q 'OMARCHY_HW_NVIDIA_GB10_' "$DETECTOR"; then
  fail "production detection ignores caller-provided fixture overrides"
fi
pass "production detection always reads real uname and sysfs"

(
  export HOME="$FIXTURE/home"
  export OMARCHY_ARM_IMAGE_INSTALL=1
  export OMARCHY_ARM_PLATFORM=n1x
  mkdir -p "$HOME/.config/hypr"
  : > "$HOME/.config/hypr/envs.lua"

  uname() { printf '%s\n' aarch64; }
  omarchy-hw-nvidia-gb10() { return 1; }
  omarchy-pkg-add() { printf '%s\n' "$*" > "$FIXTURE/nvidia-packages"; }
  pacman() {
    case "$*" in
      '-Q nvidia-open-dkms') printf 'nvidia-open-dkms 610.57.04-1\n' ;;
      '-Q nvidia-utils') printf 'nvidia-utils 610.57.04-1\n' ;;
      '-Q linux-n1x-headers libva-nvidia-driver') return 0 ;;
      *) return 1 ;;
    esac
  }
  sudo() {
    if [[ $1 == tee ]]; then
      command cat >/dev/null
    else
      return 0
    fi
  }

  source "$ROOT/install/config/hardware/nvidia.sh"
)
[[ $(<"$FIXTURE/nvidia-packages") == "linux-n1x-headers nvidia-open-dkms=610.57.04-1 nvidia-utils=610.57.04-1 libva-nvidia-driver" ]] \
  || fail "selects the native N1x NVIDIA driver pair without lib32 packages"
pass "selects the native N1x NVIDIA driver pair without lib32 packages"

(
  export OMARCHY_ARM_IMAGE_INSTALL=1
  export OMARCHY_ARM_PLATFORM=gb10
  uname() { printf '%s\n' aarch64; }
  omarchy-hw-nvidia-gb10() { return 1; }
  omarchy-pkg-add() { printf '%s\n' "$*" > "$FIXTURE/kernel-add"; }
  omarchy-pkg-drop() { printf '%s\n' "$*" > "$FIXTURE/kernel-drop"; }
  pacman() {
    [[ $* == '-Q linux-gb10 linux-gb10-headers' ]]
  }
  sudo() {
    if [[ $1 == tee ]]; then
      command cat >/dev/null
    else
      return 0
    fi
  }

  source "$ROOT/install/config/hardware/nvidia/gb10-kernel.sh"
)
[[ $(<"$FIXTURE/kernel-add") == "linux-gb10 linux-gb10-headers" ]] \
  || fail "installs the GB10 kernel and headers"
[[ $(<"$FIXTURE/kernel-drop") == "linux linux-headers" ]] \
  || fail "drops the generic kernel only on GB10"
pass "installs GB10 kernel pair and drops the generic kernel"

(
  export OMARCHY_ARM_IMAGE_INSTALL=1
  export OMARCHY_ARM_PLATFORM=n1x
  uname() { printf '%s\n' aarch64; }
  omarchy-pkg-add() { printf '%s\n' "$*" > "$FIXTURE/n1x-kernel-add"; }
  omarchy-pkg-drop() { printf '%s\n' "$*" > "$FIXTURE/n1x-kernel-drop"; }
  pacman() {
    [[ $* == '-Q linux-n1x linux-n1x-headers' ]]
  }
  sudo() {
    if [[ $1 == tee ]]; then
      command cat >/dev/null
    else
      return 0
    fi
  }

  source "$ROOT/install/config/hardware/nvidia/n1x-kernel.sh"
)
[[ $(<"$FIXTURE/n1x-kernel-add") == "linux-n1x linux-n1x-headers" ]] \
  || fail "installs the N1x kernel and headers"
[[ $(<"$FIXTURE/n1x-kernel-drop") == "linux linux-headers" ]] \
  || fail "drops the generic kernel only after N1x installation"
pass "installs N1x kernel pair and drops the generic kernel"

if (
  export OMARCHY_ARM_IMAGE_INSTALL=1
  export OMARCHY_ARM_PLATFORM=gb10
  uname() { printf '%s\n' aarch64; }
  omarchy-hw-nvidia-gb10() { return 1; }
  omarchy-pkg-add() { return 1; }
  omarchy-pkg-drop() { printf 'unexpected\n' >"$FIXTURE/kernel-drop-on-failure"; }
  source "$ROOT/install/config/hardware/nvidia/gb10-kernel.sh"
); then
  fail "propagates GB10 kernel transaction failures"
fi
[[ ! -e $FIXTURE/kernel-drop-on-failure ]] || fail "keeps the generic kernel when GB10 installation fails"
pass "keeps the generic kernel and fails the stage on transaction failure"

if (
  uname() { printf '%s\n' aarch64; }
  export OMARCHY_ARM_PLATFORM=gb10
  omarchy-hw-nvidia-gb10() { return 0; }
  omarchy-pkg-add() { printf 'unexpected\n' >"$FIXTURE/kernel-add-without-authorization"; }
  source "$ROOT/install/config/hardware/nvidia/gb10-kernel.sh"
); then
  fail "kernel transition succeeds without ARM image authorization"
fi
[[ ! -e $FIXTURE/kernel-add-without-authorization ]] || fail "kernel transition mutates without ARM image authorization"

if (
  uname() { printf '%s\n' aarch64; }
  export OMARCHY_ARM_PLATFORM=n1x
  omarchy-hw-nvidia-gb10() { return 0; }
  omarchy-pkg-add() { printf 'unexpected\n' >"$FIXTURE/nvidia-add-without-authorization"; }
  source "$ROOT/install/config/hardware/nvidia.sh"
); then
  fail "NVIDIA stage succeeds without ARM image authorization"
fi
[[ ! -e $FIXTURE/nvidia-add-without-authorization ]] || fail "NVIDIA stage mutates without ARM image authorization"
pass "requires explicit image authorization for mandatory AArch64 stages"

grep -Fq 'authorized development installer image' "$ROOT/install/preflight/guard.sh" \
  || fail "AArch64 direct and online installs are rejected"
pass "rejects incomplete AArch64 direct and online installs"

boot_guard_line=$(grep -n -m1 'Omarchy online installation is unavailable on ARM' "$ROOT/boot.sh" | cut -d: -f1)
boot_mutation_line=$(grep -n -m1 'sudo tee /etc/pacman.d/mirrorlist' "$ROOT/boot.sh" | cut -d: -f1)
if [[ -z $boot_guard_line || -z $boot_mutation_line || $boot_guard_line -ge $boot_mutation_line ]]; then
  fail "online ARM rejection occurs before bootstrap mutations"
fi
pass "rejects online ARM installation before bootstrap mutations"

grep -Fq 'OMARCHY_ARM_IMAGE_INSTALL' "$ROOT/install/preflight/guard.sh" \
  || fail "AArch64 preflight omits explicit image authorization"
pass "requires explicit AArch64 image authorization"

for guarded_command in omarchy-channel-set omarchy-migrate omarchy-reinstall-pkgs omarchy-refresh-pacman omarchy-update omarchy-update-aur-pkgs omarchy-update-available-reset omarchy-update-branch omarchy-update-firmware omarchy-update-git omarchy-update-keyring omarchy-update-orphan-pkgs omarchy-update-perform omarchy-update-restart omarchy-update-system-pkgs omarchy-update-time omarchy-branch-set; do
  grep -Fq 'install/helpers/gb10-lifecycle.sh' "$ROOT/bin/$guarded_command" \
    || fail "loads the shared GB10 lifecycle guard in $guarded_command"
  grep -Fq 'omarchy-guard-gb10-lifecycle' "$ROOT/bin/$guarded_command" \
    || fail "runs the shared GB10 lifecycle guard in $guarded_command"
  grep -Eq 'omarchy-guard-gb10-lifecycle .*\|\| exit 1' "$ROOT/bin/$guarded_command" \
    || fail "exits explicitly when the GB10 lifecycle guard fails in $guarded_command"
done
grep -Fq '$(uname -m) != x86_64' "$ROOT/bin/omarchy-upgrade-to-quattro" \
  || fail "guards the self-contained Quattro migration on all non-x86 systems"
if (
  uname() { printf '%s\n' aarch64; }
  source "$ROOT/install/helpers/gb10-lifecycle.sh"
  omarchy-guard-gb10-lifecycle "Test operation"
); then
  fail "lifecycle guard fails open on AArch64 when hardware detection is unavailable"
fi
(
  uname() { printf '%s\n' x86_64; }
  source "$ROOT/install/helpers/gb10-lifecycle.sh"
  omarchy-guard-gb10-lifecycle "Test operation"
) || fail "lifecycle guard rejects x86_64"
pass "guards all public Omarchy Git and update lifecycle entry points"

install_arch_guard_line=$(grep -n -m1 'OMARCHY_ARM_IMAGE_INSTALL' "$ROOT/install.sh" | cut -d: -f1)
install_helper_line=$(grep -n -m1 'helpers/all.sh' "$ROOT/install.sh" | cut -d: -f1)
if [[ -z $install_arch_guard_line || -z $install_helper_line || $install_arch_guard_line -ge $install_helper_line ]]; then
  fail "unsupported AArch64 is rejected before mutating installer helpers load"
fi
pass "rejects unsupported AArch64 before helper mutations"

for unlocked_install_file in \
  install.sh \
  install/preflight/guard.sh \
  install/config/hardware/nvidia.sh \
  install/config/hardware/nvidia/gb10-kernel.sh \
  install/config/hardware/nvidia/n1x-kernel.sh \
  install/config/hardware/nvidia/n1x-recovery.sh \
  install/login/limine-snapper.sh; do
  if grep -Fq 'omarchy-hw-nvidia-gb10' "$ROOT/$unlocked_install_file"; then
    fail "N1x install path remains locked to Coleman hardware in $unlocked_install_file"
  fi
done
pass "does not classify the authorized N1x image as Coleman GB10 hardware"

grep -Fq 'arch_keyring=archlinuxarm-keyring' "$ROOT/bin/omarchy-update-keyring" \
  || fail "updates the Arch Linux ARM keyring on GB10"
grep -Fq '$(uname -m) == aarch64' "$ROOT/install/post-install/pacman.sh" \
  || fail "selects the ARM pacman configuration without detector permission"
pass "updates the Arch Linux ARM keyring on GB10"

grep -Fq '/boot/EFI/limine/limine_aa64.efi' "$ROOT/install/login/limine-snapper.sh" \
  || fail "validates the installed AArch64 Limine loader"
grep -Fq '/boot/EFI/BOOT/BOOTAA64.EFI' "$ROOT/install/login/limine-snapper.sh" \
  || fail "validates the AArch64 fallback loader"
grep -Fq 'replacement_entry_ready' "$ROOT/install/login/limine-snapper.sh" \
  || fail "preserves Archinstall NVRAM entry until its replacement is verified"
pass "validates AArch64 Limine deployment before removing the installer entry"

grep -Fq 'mkinitcpio_hooks=${mkinitcpio_hooks/ plymouth/}' "$ROOT/install/login/limine-snapper.sh" \
  || fail "installed AArch64 initramfs still includes the crashing Plymouth hook"
grep -Fq 'KERNEL_CMDLINE[default]+=" console=tty0 acpi=nospcr disablehooks=plymouth plymouth.enable=0 loglevel=7 ignore_loglevel systemd.show_status=1 rd.udev.log_level=info vt.global_cursor_default=1"' "$ROOT/install/login/limine-snapper.sh" \
  || fail "installed AArch64 Limine entry does not pin the panel console or still starts Plymouth"
grep -Fq 'sed -i '"'"'/^KERNEL_CMDLINE\[default\]+=" quiet splash loglevel=0 /d'"'"' /etc/default/limine' "$ROOT/install/login/limine-snapper.sh" \
  || fail "installed AArch64 boot failures remain hidden by quiet defaults"
if grep -Fq 'later values override the quiet defaults' "$ROOT/install/login/limine-snapper.sh"; then
  fail "installer still assumes limine-entry-tool appends += lines in order"
fi
grep -Fq 'KERNEL_CMDLINE[linux-n1x-rescue]=' "$ROOT/install/login/limine-snapper.sh" \
  || fail "N1x rescue entry inherits the normal cmdline through Limine load options"
grep -Fq 'n1x_rescue_entry_cmdline) != "$N1X_RESCUE_CMDLINE"' "$ROOT/install/login/limine-snapper.sh" \
  || fail "N1x rescue entry cmdline is not verified in /boot/limine.conf"
grep -Fq 'an AArch64 Limine entry still boots quietly' "$ROOT/install/login/limine-snapper.sh" \
  || fail "generated AArch64 entries are not checked for quiet boot"
plymouth_disable_line=$(grep -n -m1 'disablehooks=plymouth plymouth.enable=0' "$ROOT/install/login/limine-snapper.sh" | cut -d: -f1)
limine_hook_install_line=$(grep -n -m1 'limine-snapper-sync limine-mkinitcpio-hook' "$ROOT/install/login/limine-snapper.sh" | cut -d: -f1)
if [[ -z $plymouth_disable_line || -z $limine_hook_install_line || $plymouth_disable_line -ge $limine_hook_install_line ]]; then
  fail "installed AArch64 Plymouth disablement runs after Limine UKI generation"
fi
pass "disables crashing Plymouth before installed AArch64 UKI generation"

grep -Fq 'limine-entry-tool --add-uki linux-n1x-rescue' "$ROOT/install/login/limine-snapper.sh" \
  || fail "N1x does not generate a compact rescue UKI"
grep -Fq -- '--no-mutex --no-hooks' "$ROOT/install/login/limine-snapper.sh" \
  || fail "N1x rescue UKI installation can recursively run boot hooks"
if grep -Fq 'MKINITCPIO_FALLBACK=linux-n1x' "$ROOT/install/login/limine-snapper.sh"; then
  fail "N1x still requests the oversized generic fallback initramfs"
fi
grep -Fq 'omarchy.n1x_recovery=1' "$ROOT/install/login/limine-snapper.sh" \
  || fail "N1x diagnostic recovery has no boot marker"
grep -Fq 'nomodeset module_blacklist=nvidia,nvidia_drm,nvidia_modeset,nvidia_uvm,nvidia_peermem,nouveau' "$ROOT/install/login/limine-snapper.sh" \
  || fail "N1x diagnostic rescue does not blacklist NVIDIA"
grep -Fq 'systemd.unit=multi-user.target console=tty0 fbcon=map:0 earlycon' "$ROOT/install/login/limine-snapper.sh" \
  || fail "N1x diagnostic rescue does not boot to the console target"
grep -Fq 'MODULES+=(i2c_tegra i2c_hid i2c_hid_acpi hid_generic hid_multitouch usbhid)' "$ROOT/install/config/hardware/nvidia/n1x-kernel.sh" \
  || fail "N1x installed initramfs does not preserve internal and USB keyboards"
grep -Fq 'options nvidia_drm modeset=0' "$ROOT/install/config/hardware/nvidia.sh" \
  || fail "N1x does not defer NVIDIA DRM modesetting"
grep -Fq 'sudo rm -f /etc/mkinitcpio.conf.d/nvidia.conf' "$ROOT/install/config/hardware/nvidia.sh" \
  || fail "N1x leaves forced NVIDIA initramfs modules enabled"
grep -Fq 'chrootable_systemctl_enable sshd.service' "$ROOT/install/config/hardware/nvidia/n1x-recovery.sh" \
  || fail "N1x recovery does not enable SSH"
grep -Fq 'PasswordAuthentication no' "$ROOT/install/config/hardware/nvidia/n1x-recovery.sh" \
  || fail "N1x recovery permits SSH password authentication"
grep -Fq 'PermitRootLogin no' "$ROOT/install/config/hardware/nvidia/n1x-recovery.sh" \
  || fail "N1x recovery permits SSH root login"
grep -Fq 'chrootable_systemctl_enable systemd-networkd.service' "$ROOT/install/config/hardware/nvidia/n1x-recovery.sh" \
  || fail "N1x recovery does not enable Ethernet DHCP"
grep -Fq 'chrootable_systemctl_enable systemd-resolved.service' "$ROOT/install/config/hardware/nvidia/n1x-recovery.sh" \
  || fail "N1x recovery does not enable local hostname discovery"
grep -Fq 'omarchy-n1x-probe.service' "$ROOT/install/config/hardware/nvidia/n1x-recovery.sh" \
  || fail "N1x recovery does not install the automated hardware probe"
pass "provides keyboard, conservative console, SSH, and hardware-probe recovery for N1x"

grep -Fq 'bash -Ee -o pipefail' "$ROOT/install/helpers/logging.sh" \
  || fail "GB10 logged stages propagate command and pipeline failures"
pass "propagates failures from every GB10 installer stage"

grep -Fq 'snapper --no-dbus list-configs' "$ROOT/install/login/limine-snapper.sh" \
  || fail "Limine finalization still queries Snapper through unavailable D-Bus"
grep -Fq 'snapper --no-dbus -c root create-config /' "$ROOT/install/login/limine-snapper.sh" \
  || fail "Limine finalization still creates the root config through unavailable D-Bus"
pass "uses Snapper's direct backend before Limine finalization"

grep -Fq 'log_lines < 8' "$ROOT/install/helpers/errors.sh" \
  || fail "small installer consoles keep a visible failure-log tail"
(
  gum() { return 0; }
  less() { printf '%s\n' "$*" >"$FIXTURE/debug-less-args"; }

  source "$ROOT/install/helpers/errors.sh"
  trap - ERR INT TERM EXIT

  OMARCHY_INSTALL_LOG_FILE="$FIXTURE/omarchy-install.log"
  printf '%s\n' "specific AArch64 image failure" >"$OMARCHY_INSTALL_LOG_FILE"
  OMARCHY_INSTALL_DEBUG_LOGS=1
  show_debug_log

  [[ $(<"$FIXTURE/debug-less-args") == "-R +G -- $OMARCHY_INSTALL_LOG_FILE" ]]
) || fail "AArch64 image diagnostic mode opens the complete installer log at its end"
pass "shows complete AArch64 image failure logs in explicit diagnostic mode"

grep -Fq 'cleanup_chroot_installer_sudoers' "$ROOT/install/helpers/errors.sh" \
  || fail "chroot install errors remove the temporary sudo policy"
grep -Fq '99-omarchy-installer' "$ROOT/install/helpers/errors.sh" \
  || fail "error cleanup targets the temporary installer sudo policy"
(
  source "$ROOT/install/helpers/errors.sh"
  trap - ERR INT TERM EXIT
  OMARCHY_CHROOT_INSTALL=1
  sudo() { return 1; }
  cleanup_chroot_installer_sudoers \
    || exit 1
  unset OMARCHY_CHROOT_INSTALL
  policy_path="$FIXTURE/99-omarchy-installer"
  touch "$policy_path"
  cleanup_installer_sudoers_path "$policy_path"
  [[ ! -e $policy_path ]] || exit 1
  touch "$policy_path"
  rm() { return 1; }
  ! cleanup_installer_sudoers_path "$policy_path"
  [[ -e $policy_path ]]
) || fail "verifies temporary sudo-policy removal and propagates removal failure"
pass "removes unrestricted installer sudo on all chroot exits"

grep -Fq '$(uname -m) == aarch64' "$ROOT/install/config/hardware/nvidia/gb10-kernel.sh" \
  || fail "kernel stage selects mandatory AArch64 work by architecture"
grep -Fq 'authorization disappeared before NVIDIA driver installation' "$ROOT/install/config/hardware/nvidia.sh" \
  || fail "NVIDIA stage fails when ARM image authorization disappears"
grep -Fq 'authorization disappeared before Limine validation' "$ROOT/install/login/limine-snapper.sh" \
  || fail "Limine stage fails when ARM image authorization disappears"
limine_guard_line=$(grep -n -m1 'authorization disappeared before Limine finalization' "$ROOT/install/login/limine-snapper.sh" | cut -d: -f1)
limine_mutation_line=$(grep -n -m1 'sudo tee /etc/mkinitcpio.conf.d/omarchy_hooks.conf' "$ROOT/install/login/limine-snapper.sh" | cut -d: -f1)
if [[ -z $limine_guard_line || -z $limine_mutation_line || $limine_guard_line -ge $limine_mutation_line ]]; then
  fail "Limine authorization guard runs after bootloader mutation"
fi
pass "revalidates ARM image authorization in mandatory AArch64 stages"

grep -Fq 'clear || true' "$ROOT/boot.sh" \
  || fail "noninteractive x86 bootstrap tolerates an unset TERM"
pass "preserves noninteractive x86 bootstrap under errexit"
