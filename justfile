set shell := ["bash", "-euo", "pipefail", "-c"]

# Affiche la liste des recettes
default:
  @just --list

# Installe les dépendances (alsa-tools, alsa-utils, libnotify)
deps:
  bash scripts/deps.sh

# Diagnostique la carte son et propose un test interactif
diagnose:
  bin/jackless diagnose --interactive

# Installe jackless (sudo) et migre les anciens fichiers de l'utilisateur
install: deps
  sudo bash scripts/install.sh
  bash scripts/migrate-legacy.sh user

# Désinstalle jackless et rétablit les haut-parleurs (garde la configuration)
uninstall:
  bash scripts/shortcut.sh remove || true
  sudo bash scripts/uninstall.sh

# Désinstalle jackless et supprime aussi la configuration
purge:
  bash scripts/shortcut.sh remove || true
  sudo bash scripts/uninstall.sh --purge

# Vérifie que jackless est installé (recette interne)
_require:
  @test -x /usr/local/bin/jackless || { echo "jackless n'est pas installé : lance d'abord « just install »" >&2; exit 1; }

# Bascule entre casque et haut-parleurs
toggle: _require
  /usr/local/bin/jackless toggle

# Coupe les haut-parleurs (mode casque)
headphones: _require
  /usr/local/bin/jackless headphones

# Rétablit les haut-parleurs
speakers: _require
  /usr/local/bin/jackless speakers

# Affiche l'état courant
status: _require
  /usr/local/bin/jackless status

# Remet l'audio dans un état connu
reset: _require
  /usr/local/bin/jackless reset

# Ajoute un raccourci clavier global (KDE Plasma 6), Meta+Alt+H par défaut
shortcut key="Meta+Alt+H":
  bash scripts/shortcut.sh add "{{key}}"

# Supprime le raccourci clavier
shortcut-remove:
  bash scripts/shortcut.sh remove

# Met à jour le dépôt puis réinstalle
update:
  git pull --ff-only
  just install

# Analyse les scripts avec shellcheck
lint:
  shellcheck -x bin/jackless bin/jackless-pin lib/jackless/common.sh systemd/jackless-sleep scripts/*.sh tests/*.sh

# Vérifie la syntaxe, le lint, la détection et les aides en ligne
test:
  for script in bin/jackless bin/jackless-pin lib/jackless/common.sh systemd/jackless-sleep scripts/*.sh tests/*.sh; do bash -n "$script"; done
  just lint
  bash tests/detect.sh
  bin/jackless --help >/dev/null
  bin/jackless-pin --help >/dev/null

# Crée le dépôt GitHub (visibility : public ou private) et pousse
publish visibility="private":
  case "{{visibility}}" in public|private) ;; *) echo "visibility doit valoir public ou private" >&2; exit 1 ;; esac
  gh repo create jackless --{{visibility}} --source . --push
