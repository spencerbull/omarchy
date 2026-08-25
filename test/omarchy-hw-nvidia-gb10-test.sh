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
  mkdir -p "$HOME/.config/hypr"
  : > "$HOME/.config/hypr/envs.lua"

  uname() { printf '%s\n' aarch64; }
  omarchy-hw-nvidia-gb10() { return 0; }
  omarchy-pkg-add() { printf '%s\n' "$*" > "$FIXTURE/nvidia-packages"; }
  pacman() {
    case "$*" in
      '-Q nvidia-open-dkms') printf 'nvidia-open-dkms 610.57.04-1\n' ;;
      '-Q nvidia-utils') printf 'nvidia-utils 610.57.04-1\n' ;;
      '-Q linux-gb10-headers libva-nvidia-driver') return 0 ;;
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
[[ $(<"$FIXTURE/nvidia-packages") == "linux-gb10-headers nvidia-open-dkms=610.57.04-1 nvidia-utils=610.57.04-1 libva-nvidia-driver" ]] \
  || fail "selects the native GB10 NVIDIA driver pair without lib32 packages"
pass "selects the native GB10 NVIDIA driver pair without lib32 packages"

(
  uname() { printf '%s\n' aarch64; }
  omarchy-hw-nvidia-gb10() { return 0; }
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

if (
  uname() { printf '%s\n' aarch64; }
  omarchy-hw-nvidia-gb10() { return 0; }
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
  omarchy-hw-nvidia-gb10() { return 1; }
  omarchy-pkg-add() { printf 'unexpected\n' >"$FIXTURE/kernel-add-on-detector-loss"; }
  source "$ROOT/install/config/hardware/nvidia/gb10-kernel.sh"
); then
  fail "kernel transition succeeds after exact GB10 evidence disappears"
fi
[[ ! -e $FIXTURE/kernel-add-on-detector-loss ]] || fail "kernel transition mutates after detector loss"

if (
  uname() { printf '%s\n' aarch64; }
  omarchy-hw-nvidia-gb10() { return 1; }
  omarchy-pkg-add() { printf 'unexpected\n' >"$FIXTURE/nvidia-add-on-detector-loss"; }
  source "$ROOT/install/config/hardware/nvidia.sh"
); then
  fail "NVIDIA stage succeeds after exact GB10 evidence disappears"
fi
[[ ! -e $FIXTURE/nvidia-add-on-detector-loss ]] || fail "NVIDIA stage mutates after detector loss"
pass "fails mandatory AArch64 hardware stages when exact GB10 evidence disappears"

grep -Fq 'direct and online installs are not available' "$ROOT/install/preflight/guard.sh" \
  || fail "GB10 direct and online installs are rejected"
pass "rejects incomplete GB10 direct and online installs"

boot_guard_line=$(grep -n -m1 'Omarchy online installation is unavailable on ARM' "$ROOT/boot.sh" | cut -d: -f1)
boot_mutation_line=$(grep -n -m1 'sudo tee /etc/pacman.d/mirrorlist' "$ROOT/boot.sh" | cut -d: -f1)
if [[ -z $boot_guard_line || -z $boot_mutation_line || $boot_guard_line -ge $boot_mutation_line ]]; then
  fail "online ARM rejection occurs before bootstrap mutations"
fi
pass "rejects online ARM installation before bootstrap mutations"

grep -Fq 'unsupported on this architecture' "$ROOT/install/preflight/guard.sh" \
  || fail "unsupported AArch64 is rejected without the overridable abort helper"
pass "hard-rejects unsupported AArch64 platforms"

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

install_arch_guard_line=$(grep -n -m1 'exact NVIDIA GB10 platform are accepted' "$ROOT/install.sh" | cut -d: -f1)
install_helper_line=$(grep -n -m1 'helpers/all.sh' "$ROOT/install.sh" | cut -d: -f1)
if [[ -z $install_arch_guard_line || -z $install_helper_line || $install_arch_guard_line -ge $install_helper_line ]]; then
  fail "unsupported AArch64 is rejected before mutating installer helpers load"
fi
pass "rejects unsupported AArch64 before helper mutations"

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

grep -Fq 'bash -Ee -o pipefail' "$ROOT/install/helpers/logging.sh" \
  || fail "GB10 logged stages propagate command and pipeline failures"
pass "propagates failures from every GB10 installer stage"

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
grep -Fq 'evidence disappeared before NVIDIA driver installation' "$ROOT/install/config/hardware/nvidia.sh" \
  || fail "NVIDIA stage fails when exact GB10 evidence disappears"
grep -Fq 'evidence disappeared before Limine validation' "$ROOT/install/login/limine-snapper.sh" \
  || fail "Limine stage fails when exact GB10 evidence disappears"
limine_guard_line=$(grep -n -m1 'evidence disappeared before Limine finalization' "$ROOT/install/login/limine-snapper.sh" | cut -d: -f1)
limine_mutation_line=$(grep -n -m1 'sudo tee /etc/mkinitcpio.conf.d/omarchy_hooks.conf' "$ROOT/install/login/limine-snapper.sh" | cut -d: -f1)
if [[ -z $limine_guard_line || -z $limine_mutation_line || $limine_guard_line -ge $limine_mutation_line ]]; then
  fail "Limine detector-loss guard runs after bootloader mutation"
fi
pass "revalidates exact GB10 evidence in mandatory AArch64 stages"

grep -Fq 'clear || true' "$ROOT/boot.sh" \
  || fail "noninteractive x86 bootstrap tolerates an unset TERM"
pass "preserves noninteractive x86 bootstrap under errexit"
