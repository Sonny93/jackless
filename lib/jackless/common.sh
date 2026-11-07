# shellcheck shell=bash
# Shared helpers for the jackless user command, sourced by bin/jackless.
# Sourcing has no side effects: no hardware probing, no exit, no config read.

readonly HELPER_PATH=/usr/local/bin/jackless-pin
readonly CONFIG_FILE=/etc/jackless.conf
readonly SUDO_MISSING_MESSAGE='règle sudoers absente ou jackless-pin non installé : lance « just install »'

readonly CONFIG_SKIP_PATTERN='^[[:space:]]*(#.*)?$'
readonly CONFIG_LINE_PATTERN='^[[:space:]]*([A-Z_]+)[[:space:]]*=[[:space:]]*(.*[^[:space:]])?[[:space:]]*$'
readonly QUOTED_VALUE_PATTERN='^"(.*)"$'
readonly STATUS_KEY_PATTERN='^[A-Za-z0-9_]+$'
readonly CARD_PATTERN='^[A-Za-z0-9_]+$'
readonly DEVICE_PATTERN='^(/dev/snd/hwC[0-9]+D[0-9]+)?$'
readonly PINS_PATTERN='^(0x[0-9a-fA-F]{1,2}([[:space:]]+0x[0-9a-fA-F]{1,2})*)?$'
readonly HEADPHONE_CONTROL_PATTERN='^[A-Za-z0-9 _-]+$'
readonly SINK_PATTERN='^[A-Za-z0-9._:-]*$'
readonly NOTIFY_PATTERN='^[01]$'

declare -A HELPER_STATUS=()

print_error() {
  printf 'jackless: %s\n' "$*" >&2
}

print_warning() {
  printf 'jackless: attention : %s\n' "$*" >&2
}

print_info() {
  printf '%s\n' "$*"
}

# shellcheck disable=SC2034
set_config_defaults() {
  printf -v CARD '%s' PCH
  printf -v HEADPHONE_CONTROL '%s' Headphone
  printf -v SINK '%s' ''
  printf -v NOTIFY '%s' 1
}

get_config_pattern() {
  case "$1" in
    CARD) printf '%s' "$CARD_PATTERN" ;;
    DEVICE) printf '%s' "$DEVICE_PATTERN" ;;
    SPEAKER_PINS) printf '%s' "$PINS_PATTERN" ;;
    HEADPHONE_CONTROL) printf '%s' "$HEADPHONE_CONTROL_PATTERN" ;;
    SINK) printf '%s' "$SINK_PATTERN" ;;
    NOTIFY) printf '%s' "$NOTIFY_PATTERN" ;;
    *) return 1 ;;
  esac
}

strip_quotes() {
  local value="$1"
  if [[ $value =~ $QUOTED_VALUE_PATTERN ]]; then
    value="${BASH_REMATCH[1]}"
  fi
  printf '%s' "$value"
}

store_config_value() {
  local key="$1" value="$2" pattern
  if ! pattern="$(get_config_pattern "$key")"; then
    print_warning "clé inconnue ignorée dans $CONFIG_FILE : $key"
    return 0
  fi
  if ! [[ $value =~ $pattern ]]; then
    print_error "valeur invalide pour $key dans $CONFIG_FILE : $value"
    return 1
  fi
  case "$key" in
    CARD | HEADPHONE_CONTROL | SINK | NOTIFY) printf -v "$key" '%s' "$value" ;;
  esac
}

parse_config_line() {
  local line="$1" key value
  if [[ $line =~ $CONFIG_SKIP_PATTERN ]]; then
    return 0
  fi
  if ! [[ $line =~ $CONFIG_LINE_PATTERN ]]; then
    print_error "ligne invalide dans $CONFIG_FILE : $line"
    return 1
  fi
  key="${BASH_REMATCH[1]}"
  value="$(strip_quotes "${BASH_REMATCH[2]:-}")"
  store_config_value "$key" "$value"
}

# Reads CONFIG_FILE line by line with a key whitelist (never sourced).
# A missing file keeps the defaults; an invalid value returns 1.
load_config() {
  local line
  set_config_defaults
  if [[ ! -r $CONFIG_FILE ]]; then
    return 0
  fi
  while IFS= read -r line || [[ -n $line ]]; do
    parse_config_line "$line" || return 1
  done <"$CONFIG_FILE"
}

notify_user() {
  if [[ ${NOTIFY:-1} != 1 ]]; then
    return 0
  fi
  if ! command -v notify-send >/dev/null 2>&1; then
    return 0
  fi
  notify-send -a jackless "Audio" "$1" || true
}

report_sudo_failure() {
  print_error "$SUDO_MISSING_MESSAGE"
  notify_user "$SUDO_MISSING_MESSAGE"
}

# Runs one jackless-pin verb through non-interactive sudo and prints its stdout.
# A sudo failure (stderr starting with "sudo:") gets the French install hint.
run_helper() {
  local verb="$1" stderr_file output error_text exit_code=0
  stderr_file="$(mktemp)"
  output="$(LC_ALL=C sudo -n "$HELPER_PATH" "$verb" 2>"$stderr_file")" || exit_code=$?
  error_text="$(<"$stderr_file")"
  rm -f "$stderr_file"
  if [[ $error_text == sudo:* ]]; then
    report_sudo_failure
    return 1
  fi
  if [[ -n $error_text ]]; then
    printf '%s\n' "$error_text" >&2
  fi
  printf '%s\n' "$output"
  return "$exit_code"
}

run_pactl() {
  LC_ALL=C pactl "$@"
}

try_pactl() {
  local warning="$1"
  shift
  run_pactl "$@" >/dev/null 2>&1 || print_warning "$warning"
}

resolve_sink_target() {
  if [[ -n ${SINK:-} ]]; then
    printf '%s\n' "$SINK"
    return 0
  fi
  printf '%s\n' '@DEFAULT_SINK@'
}

resolve_sink_name() {
  if [[ -n ${SINK:-} ]]; then
    printf '%s\n' "$SINK"
    return 0
  fi
  run_pactl get-default-sink
}

set_speaker_port() {
  run_pactl set-sink-port "$(resolve_sink_target)" analog-output-speaker >/dev/null 2>&1 || true
}

get_sink_active_port() {
  run_pactl list sinks | awk -v sink="$1" '
    /^Sink #/ { inside = 0 }
    $1 == "Name:" && $2 == sink { inside = 1 }
    inside && $1 == "Active" && $2 == "Port:" { print $3 }
  ' || true
}

get_sink_ports_section() {
  run_pactl list sinks | awk -v sink="$1" '
    /^Sink #/ { inside = 0; in_ports = 0 }
    $1 == "Name:" && $2 == sink { inside = 1 }
    inside && $1 == "Ports:" { in_ports = 1 }
    inside && in_ports { print }
    inside && $1 == "Active" && $2 == "Port:" { in_ports = 0 }
  ' || true
}

# Parses key=value lines from stdin into HELPER_STATUS (no eval).
parse_status_lines() {
  local line key value
  HELPER_STATUS=()
  while IFS= read -r line; do
    if [[ $line != *=* ]]; then
      continue
    fi
    key="${line%%=*}"
    value="${line#*=}"
    if [[ $key =~ $STATUS_KEY_PATTERN ]]; then
      HELPER_STATUS["$key"]="$value"
    fi
  done
}

status_value() {
  printf '%s' "${HELPER_STATUS[$1]:-}"
}
