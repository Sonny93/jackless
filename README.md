# jackless

Mute the laptop speakers by hand when headphones are plugged in, for machines whose jack presence sensor is dead.

**English summary.** On some Dell XPS laptops (Realtek ALC289) the headphone jack sensor never reports "plugged". PipeWire never switches to headphones and sound plays from the speakers and the headphones at once. jackless mutes the speaker pins at hardware level through a small root helper and a manual toggle (command or keyboard shortcut). Target: Arch/CachyOS with PipeWire and WirePlumber, KDE Plasma 6 for the shortcut. Debian and Fedora package names are untested. Everything below is in French.

## Symptômes

- Le casque est branché mais le son sort aussi par les haut-parleurs.
- `pactl` ne propose jamais le port `analog-output-headphones` (non disponible).
- `hdajacksensetest` indique toujours `present = No` pour la prise casque.

Le capteur de présence de la prise est mort : rien ne signale jamais le branchement, donc aucune bascule automatique n'est possible.

## Principe

PipeWire reste sur le port `analog-output-speaker`. Le contrôle ALSA `Headphone` est réactivé à 100 %, et les broches des haut-parleurs sont coupées au niveau matériel (`SET_PIN_WIDGET_CONTROL 0x00` via `hda-verb`). Un petit assistant root (`jackless-pin`) fait ce travail ; la commande `jackless` l'appelle via une règle sudoers limitée à ses verbes. Pendant le mode casque, `power_save` de `snd_hda_intel` passe à 0, sinon le codec s'endort et remet les broches à zéro. Un hook de veille réapplique l'état au réveil.

## Installation

Cloner le dépôt :

```
git clone https://github.com/Sonny93/jackless.git
```

Se placer ensuite dans le dossier `jackless` créé par le clonage, puis lancer les recettes ci-dessous. Elles demandent [just](https://github.com/casey/just).

Vérifier que la carte son est reconnue (propose un test interactif avec le casque) :

```
just diagnose
```

Installer (dépendances, fichiers système, règle sudoers, migration d'anciens scripts) :

```
just install
```

Ajouter un raccourci clavier global sur KDE Plasma 6 (`Meta+Alt+H` par défaut) :

```
just shortcut
```

Une autre touche : `just shortcut Meta+Alt+J`. Hors KDE, la recette affiche la commande à associer à la touche de ton environnement.

## Utilisation

| Recette | Effet |
|---|---|
| `just toggle` | bascule casque / haut-parleurs |
| `just headphones` | coupe les haut-parleurs |
| `just speakers` | rétablit les haut-parleurs |
| `just status` | affiche l'état |
| `just reset` | remet l'audio dans un état connu |
| `just update` | met à jour le dépôt puis réinstalle |

La commande installée `jackless` accepte les mêmes sous-commandes (`toggle`, `headphones`, `speakers`, `status`, `reset`, `diagnose`) et `--help`. Sans argument, elle bascule. Elle envoie une notification de bureau à chaque changement (réglable par `NOTIFY`).

## Configuration

Fichier `/etc/jackless.conf`, lignes `CLE=VALEUR`, guillemets optionnels, `#` pour les commentaires. Le fichier n'est jamais exécuté ; une clé inconnue donne un avertissement, une valeur invalide une erreur.

| Clé | Défaut | Rôle |
|---|---|---|
| `CARD` | `PCH` | identifiant ALSA de la carte (préférer l'identifiant à l'index, qui bouge avec un DAC USB) |
| `DEVICE` | vide (auto) | périphérique codec, `/dev/snd/hwC<N>D<M>` |
| `SPEAKER_PINS` | vide (auto) | broches à couper, ex. `0x14 0x17` |
| `HEADPHONE_CONTROL` | `Headphone` | contrôle ALSA à réactiver |
| `SINK` | vide (sortie par défaut) | sink PipeWire ciblé |
| `NOTIFY` | `1` | notifications de bureau (`0` pour les couper) |

Détection automatique des broches : une broche est retenue si son `Pin Default` contient `Speaker` sans `[N/A]`, ou si le pilote lui attache un contrôle `Speaker Playback`. Les deux ensembles sont réunis. Les broches `[N/A]` sont sinon ignorées : le BIOS les déclare absentes, et en couper une au hasard pourrait désactiver autre chose (HDMI, micro). Sur l'ALC289 du XPS, cela donne `0x14` et `0x17` (la seconde est `[N/A]` dans le BIOS mais pilotée comme haut-parleur de basses). Si ta machine diffère, `just diagnose` signale des broches candidates et `SPEAKER_PINS` permet de les forcer.

À la mise à jour, une configuration modifiée n'est jamais écrasée : la version livrée est écrite à côté dans `/etc/jackless.conf.new`, à comparer à la main.

## Pièges

Trois approches qui ne marchent pas, testées :

- Forcer le port `analog-output-headphones` dans PipeWire : le port n'est pas disponible, et forcer le choix coupe tout le son, micro compris.
- Couper les contrôles `Speaker` ou `Bass Speaker` avec `amixer` : le DAC et l'ampli sont partagés, le casque est coupé aussi.
- `options snd-hda-intel model=dell-headset-multi` : sans effet sur ce capteur.

Autres pièges :

- WirePlumber réapplique à chaque redémarrage de PipeWire, ouverture de session ou changement de port le profil `analog-output-speaker.conf`, qui contient `[Element Headphone] switch = off`. Le contrôle `Headphone` est donc remis à zéro ; l'assistant le réactive à chaque `headphones`, au réveil et via `reset`.
- `power_save` de `snd_hda_intel` remet les broches à leur état d'origine quand le codec s'endort. Le mode casque force `power_save` à 0 et restaure la valeur d'origine au retour en haut-parleurs.
- Un ancien script dans `~/.local/bin` passe avant `/usr/local/bin` dans le `PATH` et masque la commande installée. `just install` détecte et sauvegarde les anciens fichiers connus : ceux du système dans `/var/backups/jackless/` (root uniquement), ceux de ton dossier personnel dans `~/.local/share/jackless/legacy/`. Si une autre commande `jackless` précède l'installée dans le `PATH`, il te l'indique sans la supprimer.

## Désinstallation

Rétablit d'abord les haut-parleurs, puis retire les fichiers (la configuration est conservée) :

```
just uninstall
```

Supprime aussi la configuration :

```
just purge
```

Retirer seulement le raccourci clavier :

```
just shortcut-remove
```

## Limites

- Pas de détection automatique de la prise, par construction : la bascule est manuelle.
- Le mode casque force `power_save=0`, ce qui coûte un peu de batterie.
- TLP ou tuned peuvent réécrire `power_save` ; les haut-parleurs reviennent alors. La solution robuste, facultative, est un fichier dans `/etc/modprobe.d/` contenant la ligne `options snd_hda_intel power_save=0`, puis un redémarrage.
- Le hook de veille ne fonctionne qu'avec systemd.
- Les noms de paquets Debian et Fedora ne sont pas testés.

## Alternative matérielle

Un adaptateur USB-C vers jack est une carte son USB à part entière : il contourne le capteur mort et fonctionne sans rien installer.

## Développement

Analyse statique avec shellcheck :

```
just lint
```

Syntaxe, lint, test de détection et aides en ligne :

```
just test
```

La CI GitHub (`.github/workflows/ci.yml`) lance `just test` à chaque push et pull request.

## Licence

MIT, voir `LICENSE`.
