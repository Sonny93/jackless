#!/usr/bin/env bash
# detect.sh: tests the codec parsing of jackless-pin and its CLI contract (no root, no hardware).
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIR
readonly HELPER="$SCRIPT_DIR/../bin/jackless-pin"
readonly ALC289_FIXTURE="$SCRIPT_DIR/fixtures/alc289-codec0.txt"
readonly HDMI_FIXTURE="$SCRIPT_DIR/fixtures/hdmi-codec2.txt"
readonly EXIT_FAILURE=1
readonly EXIT_USAGE=2

failure_count=0

report() {
  local is_success=$1 name=$2
  if [[ $is_success == 1 ]]; then
    printf 'ok - %s\n' "$name"
    return 0
  fi
  printf 'not ok - %s\n' "$name"
  failure_count=$(( failure_count + 1 ))
}

assert_equals() {
  local name=$1 expected=$2 actual=$3
  if [[ $actual == "$expected" ]]; then
    report 1 "$name"
    return 0
  fi
  report 0 "$name"
  printf '  attendu : %s\n  obtenu  : %s\n' "$expected" "$actual" >&2
}

assert_excludes() {
  local name=$1 text=$2 forbidden=$3
  if [[ $text != *"$forbidden"* ]]; then
    report 1 "$name"
    return 0
  fi
  report 0 "$name"
  printf '  contient à tort : %s (dans %s)\n' "$forbidden" "$text" >&2
}

read_line_with_prefix() {
  local output=$1 prefix=$2 line
  while IFS= read -r line; do
    if [[ $line == "$prefix"* ]]; then
      printf '%s\n' "$line"
      return 0
    fi
  done <<< "$output"
}

get_exit_code() {
  local exit_code=0
  "$@" >/dev/null 2>&1 || exit_code=$?
  printf '%s\n' "$exit_code"
}

test_alc289_pins() {
  local output
  output=$("$HELPER" detect "$ALC289_FIXTURE")
  assert_equals "should detect 0x14 and 0x17 on ALC289" "pins=0x14 0x17" "$(read_line_with_prefix "$output" pins=)"
}

test_alc289_hints() {
  local output hints
  output=$("$HELPER" detect "$ALC289_FIXTURE")
  hints=$(read_line_with_prefix "$output" hints=)
  assert_excludes "should not hint the detected speaker pin 0x14" "$hints" 0x14
  assert_excludes "should not hint the detected speaker pin 0x17" "$hints" 0x17
  assert_excludes "should not hint the digital pin 0x1e" "$hints" 0x1e
}

test_hdmi_pins() {
  local output
  output=$("$HELPER" detect "$HDMI_FIXTURE")
  assert_equals "should detect no speaker pins on HDMI" "pins=" "$(read_line_with_prefix "$output" pins=)"
}

test_cli_contract() {
  assert_equals "should exit 0 on --help" 0 "$(get_exit_code "$HELPER" --help)"
  assert_equals "should exit 2 on an unknown verb" "$EXIT_USAGE" "$(get_exit_code "$HELPER" frobnicate)"
}

test_absolute_shebang() {
  local script first_line
  for script in "$HELPER" "$SCRIPT_DIR/../systemd/jackless-sleep"; do
    IFS= read -r first_line < "$script"
    assert_equals "should use an absolute bash shebang for root-run scripts ($(basename "$script"))" "#!/bin/bash" "$first_line"
  done
}

test_root_refusal() {
  if (( EUID == 0 )); then
    printf 'ok - should refuse status without root # SKIP running as root\n'
    return 0
  fi
  assert_equals "should exit 1 on status without root" "$EXIT_FAILURE" "$(get_exit_code "$HELPER" status)"
}

main() {
  test_alc289_pins
  test_alc289_hints
  test_hdmi_pins
  test_cli_contract
  test_absolute_shebang
  test_root_refusal
  (( failure_count == 0 ))
}

main
