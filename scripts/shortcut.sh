#!/usr/bin/env bash
# Add or remove a global keyboard shortcut running "jackless toggle" (user script).
# Usage: shortcut.sh add [KEY] | remove
set -euo pipefail

readonly DEFAULT_KEY="Meta+Alt+H"
readonly KEY_PATTERN='^[A-Za-z0-9+]+$'
readonly DESKTOP_NAME="jackless-toggle.desktop"
readonly DESKTOP_PATH="$HOME/.local/share/applications/$DESKTOP_NAME"
readonly TOGGLE_COMMAND="/usr/local/bin/jackless toggle"
readonly ACCEL_SERVICE="plasma-kglobalaccel.service"

fail() {
  echo "jackless: $*" >&2
  exit 1
}

is_kde_plasma() {
  command -v kwriteconfig6 >/dev/null 2>&1 && [[ "${XDG_CURRENT_DESKTOP:-}" == *KDE* ]]
}

has_accel_service() {
  systemctl --user cat "$ACCEL_SERVICE" >/dev/null 2>&1
}

stop_accel_service() {
  has_accel_service || return 0
  systemctl --user stop "$ACCEL_SERVICE"
}

start_accel_service() {
  if has_accel_service; then
    systemctl --user start "$ACCEL_SERVICE"
    return
  fi
  echo "jackless: service $ACCEL_SERVICE introuvable : déconnecte-toi puis reconnecte-toi pour activer le raccourci." >&2
}

rebuild_service_cache() {
  if command -v kbuildsycoca6 >/dev/null 2>&1; then
    kbuildsycoca6 >/dev/null 2>&1 || true
  fi
}

write_desktop_file() {
  mkdir -p "$(dirname "$DESKTOP_PATH")"
  cat >"$DESKTOP_PATH" <<EOF
[Desktop Entry]
Type=Application
Name=Jackless (bascule audio)
Exec=$TOGGLE_COMMAND
Icon=audio-headphones
NoDisplay=true
X-KDE-GlobalAccel-CommandShortcut=true
EOF
}

write_kde_shortcut() {
  kwriteconfig6 --file kglobalshortcutsrc --group services --group "$DESKTOP_NAME" --key _launch "$@"
}

add_kde_shortcut() {
  local key="$1"
  write_desktop_file
  stop_accel_service
  write_kde_shortcut "$key"
  rebuild_service_cache
  start_accel_service
  echo "Raccourci $key ajouté (bascule casque / haut-parleurs)."
}

remove_kde_shortcut() {
  stop_accel_service
  write_kde_shortcut --delete
  rm -f "$DESKTOP_PATH"
  rebuild_service_cache
  start_accel_service
  echo "Raccourci supprimé."
}

print_manual_binding() {
  local key="$1"
  echo "Environnement non reconnu comme KDE Plasma 6."
  echo "Associe la touche $key à la commande : $TOGGLE_COMMAND"
}

run_add() {
  local key="${1:-$DEFAULT_KEY}"
  [[ "$key" =~ $KEY_PATTERN ]] || fail "raccourci invalide : $key"
  if is_kde_plasma; then
    add_kde_shortcut "$key"
    return
  fi
  print_manual_binding "$key"
}

run_remove() {
  if is_kde_plasma; then
    remove_kde_shortcut
    return
  fi
  echo "Environnement non reconnu comme KDE Plasma 6 : supprime le raccourci à la main."
}

main() {
  [[ $EUID -ne 0 ]] || fail "à lancer en tant qu'utilisateur, pas en root"
  case "${1:-}" in
    add) run_add "${2:-}" ;;
    remove) run_remove ;;
    *) fail "usage : shortcut.sh add [TOUCHE] | remove" ;;
  esac
}

main "$@"
