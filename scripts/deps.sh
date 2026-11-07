#!/usr/bin/env bash
# Install the packages that provide the commands jackless needs (user script, uses sudo).
set -euo pipefail

readonly REQUIRED_COMMANDS=(hda-verb hdajacksensetest amixer alsactl notify-send)

fail() {
  echo "jackless: $*" >&2
  exit 1
}

list_missing_commands() {
  local command_name
  for command_name in "${REQUIRED_COMMANDS[@]}"; do
    command -v "$command_name" >/dev/null 2>&1 || echo "$command_name"
  done
}

map_command_to_package_key() {
  case "$1" in
    hda-verb | hdajacksensetest) echo "alsa-tools" ;;
    amixer | alsactl) echo "alsa-utils" ;;
    notify-send) echo "libnotify" ;;
    *) fail "commande inconnue : $1" ;;
  esac
}

list_missing_package_keys() {
  local command_name
  for command_name in "$@"; do
    map_command_to_package_key "$command_name"
  done | sort -u
}

translate_package_key() {
  local package_manager="$1"
  local package_key="$2"
  if [[ "$package_manager" == "apt-get" && "$package_key" == "libnotify" ]]; then
    echo "libnotify-bin"
    return
  fi
  echo "$package_key"
}

detect_package_manager() {
  local candidate
  for candidate in pacman apt-get dnf; do
    if command -v "$candidate" >/dev/null 2>&1; then
      echo "$candidate"
      return 0
    fi
  done
  return 0
}

print_manual_instructions() {
  {
    echo "jackless: gestionnaire de paquets non reconnu. Installe à la main :"
    echo "  Arch   : sudo pacman -S --needed alsa-tools alsa-utils libnotify"
    echo "  Debian : sudo apt-get install alsa-tools alsa-utils libnotify-bin"
    echo "  Fedora : sudo dnf install alsa-tools alsa-utils libnotify"
  } >&2
}

install_packages() {
  local package_manager="$1"
  shift
  case "$package_manager" in
    pacman) sudo pacman -S --needed --noconfirm "$@" ;;
    apt-get) sudo apt-get install -y "$@" ;;
    dnf) sudo dnf install -y "$@" ;;
  esac
}

resolve_packages() {
  local package_manager="$1"
  shift
  local package_key
  list_missing_package_keys "$@" | while IFS= read -r package_key; do
    translate_package_key "$package_manager" "$package_key"
  done
}

main() {
  local missing_commands=()
  local packages=()
  local package_manager

  mapfile -t missing_commands < <(list_missing_commands)
  if [[ ${#missing_commands[@]} -eq 0 ]]; then
    echo "Toutes les dépendances sont déjà installées."
    exit 0
  fi

  package_manager="$(detect_package_manager)"
  if [[ -z "$package_manager" ]]; then
    print_manual_instructions
    exit 1
  fi

  mapfile -t packages < <(resolve_packages "$package_manager" "${missing_commands[@]}")
  echo "Commandes manquantes : ${missing_commands[*]}"
  echo "Installation avec $package_manager : ${packages[*]}"
  install_packages "$package_manager" "${packages[@]}"
}

main "$@"
