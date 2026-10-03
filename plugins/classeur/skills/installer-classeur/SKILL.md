---
name: installer-classeur
description: Installer, réinstaller, mettre à jour ou réparer Classeur sur le Mac de la personne, depuis le dossier de l'agent. Utiliser au premier lancement de l'agent Classeur, après son ajout dans LibreAgent, quand l'application ou le moteur est absent, quand une mise à jour du plugin vient d'arriver, ou quand le moteur répond par une erreur d'accès au disque, de Codex ou de clé TypeSafe.
---

# Installer Classeur

Classeur fonctionne uniquement sur un Mac où Apple Mail est configuré. Le dossier de l'agent (clone du dépôt) contient l'application SwiftUI (`app/`), le moteur Python (`engine/`) et `build.sh`. L'installation place le moteur dans `~/Library/Application Support/Classeur/moteur` et l'application dans `~/Applications/Classeur.app`.

Exécute chaque étape, montre le résultat réel et arrête-toi avec la cause exacte au premier échec. Les commandes écrivent hors du dossier de l'agent et pilotent Mail : si le bac à sable de Codex les refuse, dis-le et demande à la personne d'autoriser l'accès complet pour ce dossier.

## 1. Vérifier l'ordinateur

1. `uname -s` doit répondre `Darwin`. Sur un autre système, y compris un ordinateur distant Linux de LibreAgent, arrête-toi : « Classeur a besoin d'un Mac avec Apple Mail. Installez l'agent sur ce Mac depuis LibreAgent. »
2. `test -d ~/Library/Mail` : sans ce dossier, demande d'ouvrir Apple Mail et d'y ajouter au moins un compte.
3. `xcrun swift --version` : sans réponse, lance `xcode-select --install` et attends que la personne termine l'installation des outils de ligne de commande.
4. `command -v uv` : sans réponse, installe-le avec `brew install uv` si Homebrew est présent ; sinon, donne le lien https://docs.astral.sh/uv/ et arrête-toi.
5. `codex login status` doit indiquer une connexion : Classeur rédige les réponses avec le compte ChatGPT de la personne par Codex CLI. Sinon, demande-lui de lancer `codex login`.

## 2. Construire et installer

Depuis la racine du dossier de l'agent : `./build.sh`. Le script crée une identité de signature locale propre à ce Mac (trousseau `classeur-signature`) pour que macOS garde les autorisations d'une version à l'autre, installe le moteur puis l'application. Vérifie ensuite :

- `~/Library/Application\ Support/Classeur/moteur/bin/classeur config` renvoie un événement `config` avec le chemin de `config.toml` ;
- `~/Applications/Classeur.app` existe.

## 3. Autorisations que seule la personne peut donner

1. Réglages Système > Confidentialité et sécurité > Accès complet au disque : ajouter **Classeur** (`~/Applications/Classeur.app`), puis relancer l'application. C'est ce qui permet de lire l'index d'Apple Mail. Pour que l'agent lance aussi le moteur depuis Codex, la même autorisation doit être donnée à l'application qui exécute Codex (Codex ou le terminal).
2. Au premier envoi, accepter « Classeur souhaite contrôler Mail ».

Ouvre le volet avec `open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"` et attends la confirmation de la personne.

## 4. Configurer

Le fichier est `~/Library/Application Support/Classeur/config.toml` (créé par `classeur config`). Demande à la personne, puis écris :

- `[identite]` : son nom, sa signature et une phrase sur son activité ;
- `[classement] moteur` : `"codex"` (Codex choisit le classeur, aucune clé supplémentaire) ou `"jev"` (modèle de décision TypeSafe, plus rapide, clé TypeSafe personnelle requise).

Pour Jev, la clé appartient à la personne. Ne la demande jamais dans la conversation et refuse-la si elle est collée : donne-lui cette commande à taper elle-même dans un terminal, qui demande la clé sans l'afficher :

    security add-generic-password -U -s com.nicolascleton.classeur -a typesafe -w

## 5. Vérifier

`~/Library/Application\ Support/Classeur/moteur/bin/classeur compter` doit renvoyer un événement `compte`. Un événement `erreur` donne la cause et la correction (accès au disque, Codex, clé TypeSafe) : applique-la puis recommence. Termine par `open ~/Applications/Classeur.app` et indique que le premier lancement propose des classeurs à partir d'un échantillon de mails.

## Mise à jour

Quand le plugin Classeur change de version, mets à jour le dossier de l'agent (`git pull --ff-only`), relance `./build.sh` et refais l'étape 5. Les autorisations macOS restent valables grâce à l'identité de signature locale.
