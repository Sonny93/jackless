#!/usr/bin/env bash
# Back up then remove legacy files of the previous speaker-pin setup.
# Usage: migrate-legacy.sh user|system (system needs root, user refuses root).
set -euo pipefail

readonly LEGACY_SUDOERS="/etc/sudoers.d/speaker-pin"
readonly LEGACY_HELPER="/usr/local/bin/speaker-pin"
readonly LEGACY_HELPER_SHA256="21c22ddf5ba832d7032e68e7c24220e88c3144079e6d4d6a433e991d57d9ad25"
readonly USER_BACKUP_RELATIVE_DIR=".local/share/jackless/legacy"
readonly SYSTEM_BACKUP_DIR="/var/backups/jackless"
readonly INSTALLED_COMMAND="/usr/local/bin/jackless"

BACKUP_DIR=""

fail() {
  echo "jackless: $*" >&2
  exit 1
}

warn() {
  echo "jackless: $*" >&2
}

prepare_backup_directory() {
  if [[ $EUID -eq 0 ]]; then
    install -d -m 700 -o root -g root "$BACKUP_DIR"
    return
  fi
  mkdir -p "$BACKUP_DIR"
}

backup_file() {
  local source_path="$1"
  local target_path
  target_path="$BACKUP_DIR/$(basename "$source_path").$(date +%Y%m%d%H%M%S)"
  prepare_backup_directory
  cp -p "$source_path" "$target_path"
  echo "Sauvegarde : $target_path"
}

remove_after_backup() {
  local path="$1"
  backup_file "$path"
  rm -f "$path"
  echo "Ancien fichier supprimé : $path"
}

is_legacy_sudoers() {
  local path="$1"
  local line
  while IFS= read -r line; do
    [[ -z "${line//[[:space:]]/}" || "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^[^[:space:]]+[[:space:]]+ALL=\(.*\)[[:space:]]+NOPASSWD:[[:space:]]*"$LEGACY_HELPER"([[:space:]].*)?$ ]] || return 1
  done <"$path"
  return 0
}

migrate_legacy_sudoers() {
  [[ -e "$LEGACY_SUDOERS" ]] || return 0
  if is_legacy_sudoers "$LEGACY_SUDOERS"; then
    remove_after_backup "$LEGACY_SUDOERS"
    return
  fi
  warn "contenu inattendu dans $LEGACY_SUDOERS : fichier ignoré, supprime-le à la main si besoin"
}

migrate_legacy_helper() {
  [[ -e "$LEGACY_HELPER" ]] || return 0
  local checksum
  checksum="$(sha256sum "$LEGACY_HELPER" | cut -d' ' -f1)"
  if [[ "$checksum" == "$LEGACY_HELPER_SHA256" ]]; then
    remove_after_backup "$LEGACY_HELPER"
    return
  fi
  warn "version inconnue de $LEGACY_HELPER : fichier ignoré, supprime-le à la main si besoin"
}

migrate_toggle_script() {
  local path="$HOME/.local/bin/audio-toggle"
  [[ -e "$path" ]] || return 0
  if grep -q 'pactl' "$path" && grep -qE 'speaker-pin|analog-output-headphones' "$path"; then
    warn "ancien script de bascule détecté : $path"
    remove_after_backup "$path"
    return
  fi
  warn "contenu inattendu dans $path : fichier ignoré"
}

migrate_fix_script() {
  local path="$HOME/audio-fix.sh"
  [[ -e "$path" ]] || return 0
  if grep -q 'alsactl init' "$path" && grep -q 'wireplumber' "$path"; then
    remove_after_backup "$path"
    return
  fi
  warn "contenu inattendu dans $path : fichier ignoré"
}

warn_shadowing_command() {
  local resolved
  resolved="$(command -v jackless || true)"
  [[ -n "$resolved" && "$resolved" != "$INSTALLED_COMMAND" ]] || return 0
  warn "$resolved passe avant $INSTALLED_COMMAND dans le PATH et masque la commande installée : supprime-le ou renomme-le"
}

run_system_mode() {
  [[ $EUID -eq 0 ]] || fail "le mode system demande root"
  BACKUP_DIR="$SYSTEM_BACKUP_DIR"
  migrate_legacy_sudoers
  migrate_legacy_helper
}

run_user_mode() {
  [[ $EUID -ne 0 ]] || fail "le mode user refuse root"
  BACKUP_DIR="$HOME/$USER_BACKUP_RELATIVE_DIR"
  migrate_toggle_script
  migrate_fix_script
  warn_shadowing_command
}

main() {
  case "${1:-}" in
    system) run_system_mode ;;
    user) run_user_mode ;;
    *) fail "usage : migrate-legacy.sh user|system" ;;
  esac
}

main "$@"
