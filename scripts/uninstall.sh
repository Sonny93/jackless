#!/usr/bin/env bash
# Remove jackless from the system. Run as root: sudo bash scripts/uninstall.sh [--purge]
set -euo pipefail

readonly BIN_DIR="/usr/local/bin"
readonly HELPER="$BIN_DIR/jackless-pin"
readonly CONFIG_PATH="/etc/jackless.conf"

fail() {
  echo "jackless: $*" >&2
  exit 1
}

parse_arguments() {
  case "${1:-}" in
    "") echo "keep" ;;
    --purge) echo "purge" ;;
    *) fail "usage : uninstall.sh [--purge]" ;;
  esac
}

restore_speakers() {
  [[ -x "$HELPER" ]] || return 0
  "$HELPER" on || echo "jackless: impossible de rétablir les haut-parleurs (ignoré)" >&2
}

remove_files() {
  rm -f /etc/sudoers.d/jackless
  rm -f "$BIN_DIR/jackless" "$HELPER"
  rm -rf /usr/local/lib/jackless
  rm -f /usr/lib/systemd/system-sleep/jackless
  rm -f /run/jackless.state /run/jackless.lock
}

remove_config() {
  local mode="$1"
  if [[ "$mode" == "purge" ]]; then
    rm -f "$CONFIG_PATH" "$CONFIG_PATH.new"
    echo "Configuration supprimée."
    return
  fi
  [[ -e "$CONFIG_PATH" ]] && echo "Configuration conservée : $CONFIG_PATH (« just purge » pour la supprimer)."
  return 0
}

main() {
  local mode
  mode="$(parse_arguments "$@")"
  [[ $EUID -eq 0 ]] || fail "à lancer en root : sudo bash scripts/uninstall.sh"
  restore_speakers
  remove_files
  remove_config "$mode"
  echo "jackless est désinstallé. Haut-parleurs rétablis."
}

main "$@"
