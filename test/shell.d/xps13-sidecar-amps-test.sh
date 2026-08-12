#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/dell-xps13-sidecar-amps.sh"
all="$ROOT/install/hardware/all.sh"
migration="$ROOT/migrations/1786510911.sh"

grep -Fq 'dell-xps13-sidecar-amps.sh' "$all" ||
  fail "the XPS 13 sidecar quirk runs during hardware setup"
pass "the XPS 13 sidecar quirk runs during hardware setup"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

dmi="$test_tmp/dmi"
modules="$test_tmp/modules"
conf="$test_tmp/etc/modprobe.d/dell-xps13-dx13260-sidecar-amps.conf"
kernel_hook="$test_tmp/etc/pacman.d/hooks/95-omarchy-xps13-sidecar-amps.hook"
active_quirk="$test_tmp/active-quirk"
repair_marker="$test_tmp/repair-complete"
cleanup_pending="$test_tmp/cleanup-pending"
lock="$test_tmp/sidecar.lock"
stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
helper_fixture="$test_tmp/dell-xps13-sidecar-amps.sh"
migration_fixture="$test_tmp/migration.sh"
mkdir -p "$dmi" "$modules" "$stub_bin"

cat >"$stub_bin/modprobe" <<'SH'
#!/bin/bash

(( ${FAIL_MODPROBE:-0} == 0 )) || exit 1
[[ $1 == "--showconfig" ]]
[[ -r ${MODPROBE_CONFIG:-} ]] && cat "$MODPROBE_CONFIG"
[[ -r ${MODPROBE_MANAGED_CONF:-} ]] && cat "$MODPROBE_MANAGED_CONF"
exit 0
SH

cat >"$stub_bin/limine-mkinitcpio" <<'SH'
#!/bin/bash

echo 'limine-mkinitcpio' >>"$TEST_LOG"
sleep "${REBUILD_DELAY:-0}"
(( ${FAIL_REBUILD:-0} == 0 ))
SH

cat >"$stub_bin/mkinitcpio" <<'SH'
#!/bin/bash

printf 'mkinitcpio' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash

printf 'sudo' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
"$@"
SH

cat >"$stub_bin/omarchy-state" <<'SH'
#!/bin/bash

printf 'omarchy-state' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH

cat >"$stub_bin/mv" <<'SH'
#!/bin/bash

if (( ${FAIL_MOVE:-0} )); then
  exit 1
fi
exec /usr/bin/mv "$@"
SH

cat >"$stub_bin/rm" <<'SH'
#!/bin/bash

for argument in "$@"; do
  target="$argument"
done
if [[ -n ${FAIL_RM_PATH:-} && $target == "$FAIL_RM_PATH" ]]; then
  exit 1
fi
exec /usr/bin/rm "$@"
SH

chmod +x "$stub_bin"/*

# Privileged production destinations stay fixed. Tests rewrite a private copy
# instead of exposing environment-controlled root paths in shipped code.
sed \
  -e "s|/sys/class/dmi/id/sys_vendor|$dmi/sys_vendor|g" \
  -e "s|/sys/class/dmi/id/product_sku|$dmi/product_sku|g" \
  -e "s|/usr/lib/modules|$modules|g" \
  -e "s|/etc/modprobe.d/dell-xps13-dx13260-sidecar-amps.conf|$conf|g" \
  -e "s|/etc/pacman.d/hooks/95-omarchy-xps13-sidecar-amps.hook|$kernel_hook|g" \
  -e "s|/sys/module/snd_soc_sof_sdw/parameters/quirk|$active_quirk|g" \
  -e "s|/var/lib/omarchy/migrations/1786510911-cleanup-pending|$cleanup_pending|g" \
  -e "s|/var/lib/omarchy/migrations/1786510911|$repair_marker|g" \
  -e "s|/run/lock/omarchy-xps13-sidecar-amps.lock|$lock|g" \
  -e 's/((EUID == 0))/true/' \
  "$leaf" >"$helper_fixture"

sed \
  -e "s|/usr/share/omarchy/install/hardware/dell-xps13-sidecar-amps.sh|$helper_fixture|g" \
  -e "s|/sys/class/dmi/id/sys_vendor|$dmi/sys_vendor|g" \
  -e "s|/sys/class/dmi/id/product_sku|$dmi/product_sku|g" \
  "$migration" >"$migration_fixture"

modprobe_config="$test_tmp/modprobe.conf"
: >"$modprobe_config"

set_hardware() {
  printf '%s' "$1" >"$dmi/sys_vendor"
  printf '%s' "$2" >"$dmi/product_sku"
  printf '%s' "$3" >"$active_quirk"
}

set_kernel_native() {
  local native="$1"
  rm -rf "$modules"
  if ((native)); then
    set_kernel_release "7.2.0-arch1-1"
  else
    set_kernel_release "7.1.8-arch1-1"
  fi
}

set_kernel_release() {
  local release="$1"
  mkdir -p "$modules/$release/kernel/sound/soc/intel/boards"
  printf 'kernel module fixture' > \
    "$modules/$release/kernel/sound/soc/intel/boards/snd-soc-sof-sdw.ko"
}

run_leaf() {
  PATH="$stub_bin:$PATH" \
    MODPROBE_CONFIG="$modprobe_config" \
    MODPROBE_MANAGED_CONF="$conf" \
    TEST_LOG="$calls" \
    FAIL_MODPROBE="${FAIL_MODPROBE:-0}" \
    FAIL_MOVE="${FAIL_MOVE:-0}" \
    FAIL_RM_PATH="${FAIL_RM_PATH:-}" \
    bash -eE -o pipefail -c 'source "$1"' bash "$helper_fixture" </dev/null
}

run_migration() {
  local script="${1:-$migration_fixture}"
  : >"$calls"
  PATH="$stub_bin:$PATH" \
    MODPROBE_CONFIG="$modprobe_config" \
    MODPROBE_MANAGED_CONF="$conf" \
    TEST_LOG="$calls" \
    FAIL_MODPROBE="${FAIL_MODPROBE:-0}" \
    FAIL_REBUILD="${FAIL_REBUILD:-0}" \
    FAIL_MOVE="${FAIL_MOVE:-0}" \
    REBUILD_DELAY="${REBUILD_DELAY:-0}" \
    bash -euo pipefail "$script" >/dev/null
}

run_kernel_update() {
  : >"$calls"
  PATH="$stub_bin:$PATH" \
    MODPROBE_CONFIG="$modprobe_config" \
    MODPROBE_MANAGED_CONF="$conf" \
    TEST_LOG="$calls" \
    FAIL_REBUILD="${FAIL_REBUILD:-0}" \
    FAIL_MOVE="${FAIL_MOVE:-0}" \
    bash -euo pipefail "$helper_fixture" --kernel-updated >/dev/null
}

set_hardware "Dell Inc." "0E53" "1"
set_kernel_native 0
run_leaf
grep -Fxq 'options snd_soc_sof_sdw quirk=65536' "$conf" ||
  fail "fresh XPS 13 setup enables the sidecar amplifiers" "$(cat "$conf" 2>&1)"
grep -Fq 'snd-soc-sof-sdw.ko*' "$kernel_hook" ||
  fail "fresh setup installs the kernel cleanup hook" "$(cat "$kernel_hook" 2>&1)"
grep -Fq -- '--kernel-updated' "$kernel_hook" ||
  fail "the kernel hook reconciles the managed override"
pass "fresh XPS 13 setup enables the quirk"
pass "kernel upgrades recheck whether the temporary override is still needed"

: >"$calls"
set_kernel_native 1
run_leaf
[[ ! -e $conf && ! -e $kernel_hook ]] ||
  fail "a later hardware apply retires the native workaround"
grep -Fxq 'limine-mkinitcpio' "$calls" ||
  fail "a later hardware apply rebuilds existing boot images" "$(cat "$calls")"
pass "a later hardware apply rebuilds before retiring the workaround"

rm -rf "$test_tmp/etc"
set_hardware "Dell Inc." "0E54" "1"
run_leaf
[[ ! -e $conf ]] || fail "another Dell SKU is left untouched"
set_hardware "LENOVO" "0E53" "1"
run_leaf
[[ ! -e $conf ]] || fail "another vendor with the same SKU is left untouched"
pass "fresh setup is gated on exact Dell vendor and SKU"

rm -rf "$test_tmp/etc"
set_hardware "Dell Inc." "0E53" "1"
set_kernel_native 1
run_leaf
[[ ! -e $conf ]] || fail "a native target kernel gets no override"
[[ ! -e $kernel_hook ]] || fail "a native target kernel gets no cleanup hook"
pass "fresh setup inspects the installed target kernel"

rm -rf "$modules" "$test_tmp/etc"
set_kernel_release "7.2.0-rc4-mainline"
run_leaf
[[ -e $conf ]] || fail "a kernel before v7.2-rc5 keeps the compatibility override"
rm -rf "$modules" "$test_tmp/etc"
set_kernel_release "7.2.0-rc5-mainline"
run_leaf
[[ ! -e $conf ]] || fail "v7.2-rc5 is recognized as the first native kernel"
rm -rf "$modules" "$test_tmp/etc"
set_kernel_release "7.2.0-arch1-1"
set_kernel_release "7.1.8-arch1-1"
run_leaf
[[ -e $conf ]] || fail "one legacy installed kernel keeps the shared override"
pass "native detection follows the upstream release boundary across installed kernels"

rm -rf "$modules" "$test_tmp/etc"
run_leaf
grep -Fxq 'options snd_soc_sof_sdw quirk=65536' "$conf" ||
  fail "an unloaded or absent target module is handled conservatively"
pass "fresh setup does not mistake an unloaded module for native support"

rm -rf "$test_tmp/etc"
set_kernel_native 0
printf 'options snd_soc_sof_sdw quirk=7\n' >"$modprobe_config"
warning="$(run_leaf 2>&1)"
[[ ! -e $conf ]] || fail "a cross-file conflict is left untouched"
[[ $warning == *"Refusing to replace"* ]] ||
  fail "fresh setup reports a cross-file conflicting quirk" "$warning"
pass "fresh setup checks the effective modprobe configuration"

rm -rf "$test_tmp/etc"
: >"$modprobe_config"
if FAIL_MOVE=1 run_leaf 2>/dev/null; then
  fail "fresh setup reports an atomic config write failure"
fi
[[ ! -e $conf ]] || fail "a failed atomic write does not install a partial override"
pass "fresh setup fails safely when its config cannot be committed"

rm -rf "$test_tmp/etc"
if FAIL_MODPROBE=1 run_migration 2>/dev/null; then
  fail "the migration refuses to write without effective modprobe state"
fi
[[ ! -e $conf ]] || fail "a failed modprobe inspection writes no override"
pass "the migration fails closed when modprobe configuration is unreadable"

rm -rf "$test_tmp/etc"
mkdir -p "$(dirname "$kernel_hook")"
printf 'user-owned hook\n' >"$kernel_hook"
warning="$(run_leaf 2>&1)"
[[ ! -e $conf ]] || fail "a kernel-hook conflict rolls back the new override"
[[ $(<"$kernel_hook") == "user-owned hook" ]] ||
  fail "a kernel-hook conflict preserves the existing hook"
[[ $warning == *"Refusing to replace existing kernel hook"* ]] ||
  fail "fresh setup reports the kernel-hook conflict" "$warning"
pass "fresh setup preserves a conflicting kernel hook"

rm -rf "$test_tmp/etc"
mkdir -p "$(dirname "$kernel_hook")"
printf 'user-owned hook\n' >"$kernel_hook"
if FAIL_RM_PATH="$conf" run_leaf 2>/dev/null; then
  fail "fresh setup propagates a failed hook-conflict rollback"
fi
[[ -e $conf ]] || fail "the rollback-failure fixture leaves its target in place"
[[ $(<"$kernel_hook") == "user-owned hook" ]] ||
  fail "failed rollback still preserves the conflicting hook"
pass "fresh setup reports an operational hook-conflict rollback failure"

rm -rf "$test_tmp/etc" "$repair_marker" "$cleanup_pending"
printf 'options snd_soc_sof_sdw quirk=7\n' >"$modprobe_config"
set_hardware "Dell Inc." "0E53" "1"
if run_migration 2>/dev/null; then
  fail "the migration refuses a cross-file conflicting quirk"
fi
[[ ! -e $conf ]] || fail "the migration preserves the conflicting configuration"
! grep -Fxq 'limine-mkinitcpio' "$calls" ||
  fail "the migration does not rebuild with a conflict" "$(cat "$calls")"
pass "the migration fails closed on an effective modprobe conflict"

: >"$modprobe_config"
mkdir -p "$(dirname "$conf")"
printf '%s' 'options snd_soc_sof_sdw debug=1' >"$conf"
run_leaf
grep -Fxq 'options snd_soc_sof_sdw debug=1' "$conf" ||
  fail "fresh setup preserves other module options" "$(cat "$conf")"
grep -Fxq 'options snd_soc_sof_sdw quirk=65536' "$conf" ||
  fail "fresh setup appends its managed block" "$(cat "$conf")"
pass "fresh setup preserves an existing target file"

rm -rf "$test_tmp/etc" "$repair_marker" "$cleanup_pending"
set_hardware "Dell Inc." "0E53" "1"
run_migration
grep -Fxq 'options snd_soc_sof_sdw quirk=65536' "$conf" ||
  fail "the migration enables the sidecar amplifiers" "$(cat "$conf" 2>&1)"
grep -Fxq 'limine-mkinitcpio' "$calls" ||
  fail "the migration rebuilds the boot image" "$(cat "$calls")"
grep -Fq $'omarchy-state\tset\treboot-required' "$calls" ||
  fail "the migration requests the required reboot" "$(cat "$calls")"
[[ -f $repair_marker ]] || fail "the migration records a successful machine repair"
pass "the migration repairs an existing XPS 13 installation"

run_migration
! grep -Fxq 'limine-mkinitcpio' "$calls" ||
  fail "a second user does not repeat the machine-wide rebuild" "$(cat "$calls")"
grep -Fq $'omarchy-state\tset\treboot-required' "$calls" ||
  fail "a second user is still told to reboot" "$(cat "$calls")"
pass "the migration is machine-idempotent before reboot"

printf '65536' >"$active_quirk"
run_migration
! grep -Fxq 'limine-mkinitcpio' "$calls" ||
  fail "an active repair does not rebuild again" "$(cat "$calls")"
! grep -Fq $'omarchy-state\tset\treboot-required' "$calls" ||
  fail "an active repair does not request another reboot" "$(cat "$calls")"
pass "the migration becomes a no-op after reboot"

rm -rf "$test_tmp/etc" "$repair_marker" "$cleanup_pending"
printf '1' >"$active_quirk"
set_kernel_native 0
: >"$calls"
REBUILD_DELAY=0.2 run_migration & first=$!
REBUILD_DELAY=0.2 run_migration & second=$!
wait "$first"
wait "$second"
(( $(grep -Fc 'options snd_soc_sof_sdw quirk=65536' "$conf") == 1 )) ||
  fail "concurrent migrations write one managed override" "$(cat "$conf")"
(( $(grep -Fxc 'limine-mkinitcpio' "$calls") == 1 )) ||
  fail "concurrent migrations run one boot rebuild" "$(cat "$calls")"
pass "the machine lock serializes concurrent user migrations"

rm -rf "$test_tmp/etc" "$repair_marker" "$cleanup_pending"
set_kernel_native 0
if FAIL_REBUILD=1 run_migration 2>/dev/null; then
  fail "a failed boot-image rebuild fails the migration"
fi
[[ ! -e $repair_marker ]] || fail "a failed rebuild does not record the repair"
run_migration
grep -Fxq 'limine-mkinitcpio' "$calls" ||
  fail "the migration retries a failed boot-image rebuild" "$(cat "$calls")"
pass "the migration retries an interrupted boot-image rebuild"

# Marker corruption is never treated as an Omarchy-owned removable block.
set_kernel_native 1
mkdir -p "$(dirname "$conf")"
printf 'user-before\n%s\nuser-middle\n%s\nuser-after\n' \
  '# END Omarchy Dell XPS 13 DX13260 sidecar amps' \
  '# BEGIN Omarchy Dell XPS 13 DX13260 sidecar amps' >"$conf"
if run_migration 2>/dev/null; then
  fail "native cleanup refuses reversed managed markers"
fi
grep -Fxq 'user-after' "$conf" ||
  fail "malformed-marker cleanup preserves all user content" "$(cat "$conf")"
pass "native cleanup fails closed on malformed managed markers"

# Gonk already has the pre-PR legacy file, without the recurring hook. A
# failed first native cleanup must still be remembered after that file moves.
rm -rf "$test_tmp/etc" "$repair_marker" "$cleanup_pending"
mkdir -p "$(dirname "$conf")"
cat >"$conf" <<'EOF'
# Temporary compatibility override for Dell XPS 13 DX13260, subsystem 1028:0e53.
# Linux mainline commit efd80de2de9d enables the same SOC_SDW_SIDECAR_AMPS
# quirk natively. Remove this file after upgrading to a kernel containing it.
options snd_soc_sof_sdw quirk=65536
EOF
if FAIL_REBUILD=1 run_migration 2>/dev/null; then
  fail "a failed legacy cleanup rebuild fails the migration"
fi
[[ ! -e $conf && -e $cleanup_pending ]] ||
  fail "legacy cleanup records pending work before removing the override"
run_migration
[[ ! -e $cleanup_pending ]] || fail "successful retry clears pending legacy cleanup"
grep -Fxq 'limine-mkinitcpio' "$calls" ||
  fail "legacy cleanup retries the required boot rebuild" "$(cat "$calls")"
pass "legacy native cleanup remains retryable without a pre-existing hook"

# A later native kernel removes only Omarchy's marked block and keeps the user's
# adjacent module option. Rebuilding retires the copy embedded in the initramfs.
rm -rf "$test_tmp/etc" "$repair_marker" "$cleanup_pending"
set_kernel_native 0
printf '1' >"$active_quirk"
run_migration
printf 'options snd_soc_sof_sdw debug=1\n%s\n' "$(sed -n '/^# BEGIN Omarchy/,/^# END Omarchy/p' "$conf")" >"$conf"
set_kernel_native 1
printf '65536' >"$active_quirk"
if FAIL_REBUILD=1 run_migration 2>/dev/null; then
  fail "a failed native cleanup rebuild fails the migration"
fi
[[ -e $kernel_hook ]] || fail "failed native cleanup keeps its retry hook"
grep -Fxq 'options snd_soc_sof_sdw debug=1' "$conf" ||
  fail "failed native cleanup preserves adjacent user configuration"
run_migration
grep -Fxq 'options snd_soc_sof_sdw debug=1' "$conf" ||
  fail "native-kernel cleanup preserves user configuration" "$(cat "$conf")"
! grep -Fq 'BEGIN Omarchy' "$conf" ||
  fail "native-kernel cleanup removes the managed block" "$(cat "$conf")"
[[ ! -e $kernel_hook ]] ||
  fail "native-kernel cleanup removes the managed kernel hook"
grep -Fxq 'limine-mkinitcpio' "$calls" ||
  fail "native-kernel cleanup rebuilds the boot image" "$(cat "$calls")"
grep -Fq $'omarchy-state\tset\treboot-required' "$calls" ||
  fail "native-kernel cleanup requests a reboot" "$(cat "$calls")"
pass "a native kernel safely retires the managed override"

# The pacman Remove path must rebuild surviving native UKIs, not merely rely on
# the normal kernel-install hook (which does not run for a removed kernel).
rm -rf "$test_tmp/etc" "$repair_marker" "$cleanup_pending" "$modules"
set_kernel_release "7.1.8-arch1-1"
printf '1' >"$active_quirk"
run_migration
rm -rf "$modules"
set_kernel_release "7.2.0-arch1-1"
run_kernel_update
[[ ! -e $conf && ! -e $kernel_hook ]] ||
  fail "the kernel Remove path retires the override and its hook"
grep -Fxq 'limine-mkinitcpio' "$calls" ||
  fail "the kernel Remove path rebuilds surviving boot images" "$(cat "$calls")"
pass "the kernel removal hook rebuilds and retires the workaround"

rm -rf "$test_tmp/etc" "$repair_marker" "$cleanup_pending"
set_kernel_native 0
printf '1' >"$active_quirk"
fallback_helper="$test_tmp/dell-xps13-sidecar-amps-no-limine.sh"
fallback_migration="$test_tmp/migration-no-limine.sh"
sed 's/command -v limine-mkinitcpio/false/' "$helper_fixture" >"$fallback_helper"
sed "s|$helper_fixture|$fallback_helper|g" "$migration_fixture" >"$fallback_migration"
run_migration "$fallback_migration"
grep -Fq $'mkinitcpio\t-P' "$calls" ||
  fail "the migration falls back to mkinitcpio" "$(cat "$calls")"
pass "the migration supports installations without limine-mkinitcpio"
