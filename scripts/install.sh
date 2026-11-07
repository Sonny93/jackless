#!/usr/bin/env bash
# Install jackless system-wide. Run as root: sudo bash scripts/install.sh
set -euo pipefail

REPO_DIR="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
readonly REPO_DIR
readonly BIN_DIR="/usr/local/bin"
readonly LIB_DIR="/usr/local/lib/jackless"
readonly CONFIG_PATH="/etc/jackless.conf"
readonly HOOK_PATH="/usr/lib/systemd/system-sleep/jackless"
readonly SUDOERS_DIR="/etc/sudoers.d"
readonly SUDOERS_TEMPORARY="$SUDOERS_DIR/.jackless.tmp"
readonly SUDOERS_FINAL="$SUDOERS_DIR/jackless"
readonly USERNAME_PATTERN='^[a-z_][a-z0-9_-]*$'
readonly HELPER="$BIN_DIR/jackless-pin"

fail() {
  echo "jackless: $*" >&2
  exit 1
}

check_prerequisites() {
  [[ $EUID -eq 0 ]] || fail "à lancer en root : sudo bash scripts/install.sh"
  [[ -n "${SUDO_USER:-}" ]] || fail "SUDO_USER absent : lance le script avec sudo"
  [[ "$SUDO_USER" =~ $USERNAME_PATTERN ]] || fail "nom d'utilisateur invalide : $SUDO_USER"
  [[ "$SUDO_USER" != "root" ]] || fail "l'installation doit être lancée depuis un utilisateur normal"
}

install_programs() {
  install -D -o root -g root -m 755 "$REPO_DIR/bin/jackless" "$BIN_DIR/jackless"
  install -D -o root -g root -m 755 "$REPO_DIR/bin/jackless-pin" "$HELPER"
  install -D -o root -g root -m 644 "$REPO_DIR/lib/jackless/common.sh" "$LIB_DIR/common.sh"
  install -D -o root -g root -m 755 "$REPO_DIR/systemd/jackless-sleep" "$HOOK_PATH"
}

install_config() {
  local shipped="$REPO_DIR/etc/jackless.conf"
  if [[ ! -e "$CONFIG_PATH" ]]; then
    install -D -o root -g root -m 644 "$shipped" "$CONFIG_PATH"
    echo "Configuration installée : $CONFIG_PATH"
    return
  fi
  if cmp -s "$shipped" "$CONFIG_PATH"; then
    return
  fi
  install -o root -g root -m 644 "$shipped" "$CONFIG_PATH.new"
  echo "Ta configuration $CONFIG_PATH diffère de la version livrée."
  echo "Elle est conservée telle quelle. La nouvelle version est dans $CONFIG_PATH.new : compare et fusionne à la main."
}

build_sudoers_line() {
  local user="$1"
  local verbs=(on off toggle status restore alsa-init)
  local rules=()
  local verb
  for verb in "${verbs[@]}"; do
    rules+=("$HELPER $verb")
  done
  local joined
  joined="$(printf '%s, ' "${rules[@]}")"
  echo "$user ALL=(root) NOPASSWD: ${joined%, }"
}

remove_sudoers_temporary() {
  rm -f "$SUDOERS_TEMPORARY"
}

install_sudoers() {
  trap remove_sudoers_temporary EXIT
  install -d -o root -g root -m 755 "$SUDOERS_DIR"
  build_sudoers_line "$SUDO_USER" >"$SUDOERS_TEMPORARY"
  chmod 440 "$SUDOERS_TEMPORARY"
  chown root:root "$SUDOERS_TEMPORARY"
  visudo -cf "$SUDOERS_TEMPORARY" >/dev/null || fail "règle sudoers invalide, installation annulée"
  mv "$SUDOERS_TEMPORARY" "$SUDOERS_FINAL"
  trap - EXIT
}

print_recap() {
  echo
  echo "jackless est installé pour l'utilisateur $SUDO_USER."
  echo "  Commandes : $BIN_DIR/jackless, $HELPER"
  echo "  Config    : $CONFIG_PATH"
  echo "  Sudoers   : $SUDOERS_FINAL"
  echo "  Veille    : $HOOK_PATH"
  echo "Essaie : jackless toggle (ou « just shortcut » pour un raccourci clavier)."
}

main() {
  check_prerequisites
  install_programs
  install_config
  install_sudoers
  bash "$REPO_DIR/scripts/migrate-legacy.sh" system
  print_recap
}

main "$@"
