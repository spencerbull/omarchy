#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
call_log="$test_tmp/calls"
leds_dir="$test_tmp/leds"
state_dir="$test_tmp/state"
device="dell::kbd_backlight"
state_file="$state_dir/omarchy/brightness/keyboard/$device"
mkdir -p "$mock_bin" "$leds_dir/$device"

cat >"$mock_bin/brightnessctl" <<'SH'
#!/bin/bash

printf '%s\n' "$*" >>"$CALL_LOG"
if [[ $* == *" max" ]]; then
  printf '%s\n' "${KBD_MAX:-2}"
elif [[ $* == *" get" ]]; then
  printf '%s\n' "${KBD_CURRENT:-0}"
fi
SH

cat >"$mock_bin/omarchy-osd" <<'SH'
#!/bin/bash
exit 0
SH

chmod +x "$mock_bin/brightnessctl" "$mock_bin/omarchy-osd"

run_keyboard() {
  CALL_LOG="$call_log" KBD_MAX="${KBD_MAX:-2}" KBD_CURRENT="${KBD_CURRENT:-0}" \
    XDG_STATE_HOME="$state_dir" OMARCHY_LEDS_DIR="$leds_dir" \
    PATH="$mock_bin:$PATH" "$ROOT/bin/omarchy-brightness-keyboard" "$@"
}

last_set() {
  sed -n 's/.* set //p' "$call_log" | tail -n 1
}

KBD_CURRENT=2 run_keyboard off
[[ $(<"$state_file") == "2" ]] || fail "blanking saves a lit keyboard backlight"
[[ $(last_set) == "0" ]] || fail "blanking turns a lit keyboard backlight off"
pass "blanking saves a lit keyboard backlight before turning it off"

: >"$call_log"
KBD_CURRENT=0 run_keyboard off
[[ $(<"$state_file") == "2" ]] || fail "firmware inactivity does not overwrite keyboard state"
[[ -z $(last_set) ]] || fail "an inactivity-blanked keyboard is not explicitly turned off again"
pass "firmware inactivity preserves the saved keyboard backlight state"

: >"$call_log"
KBD_CURRENT=0 run_keyboard restore
[[ $(last_set) == "2" ]] || fail "restore applies the last non-zero keyboard brightness"
pass "restore applies the last non-zero keyboard backlight state"

rm -f "$state_file"
: >"$call_log"
KBD_CURRENT=2 run_keyboard restore
[[ $(last_set) == "2" ]] || fail "restore preserves a lit keyboard without saved state"
[[ $(<"$state_file") == "2" ]] || fail "restore initializes state from a lit keyboard"
pass "restore initializes missing state from a lit keyboard backlight"

rm -f "$state_file"
: >"$call_log"
KBD_CURRENT=0 run_keyboard restore
[[ $(last_set) == "1" ]] || fail "restore uses a midpoint without saved keyboard state"
[[ $(<"$state_file") == "1" ]] || fail "restore persists its midpoint fallback"
pass "restore uses and saves a midpoint fallback on the first idle cycle"

printf 'invalid\n' >"$state_file"
: >"$call_log"
KBD_MAX=8 KBD_CURRENT=0 run_keyboard restore
[[ $(last_set) == "4" ]] || fail "restore replaces invalid keyboard state with a midpoint"
pass "restore rejects invalid keyboard backlight state"

printf '20\n' >"$state_file"
: >"$call_log"
KBD_MAX=8 KBD_CURRENT=0 run_keyboard restore
[[ $(last_set) == "8" ]] || fail "restore clamps keyboard state to the device maximum"
pass "restore clamps saved keyboard state to the current device maximum"

printf '2\n' >"$state_file"
: >"$call_log"
KBD_MAX=2 KBD_CURRENT=2 run_keyboard cycle
[[ $(last_set) == "0" ]] || fail "cycle can turn the keyboard backlight off"
[[ $(<"$state_file") == "2" ]] || fail "an explicit zero does not replace the last non-zero state"
pass "manual brightness changes preserve the last non-zero keyboard state"
