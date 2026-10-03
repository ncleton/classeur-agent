---
name: installer-classeur
description: Installer, réinstaller, mettre à jour ou réparer Classeur sur le Mac de la personne, depuis le dossier de l'agent. Utiliser au premier lancement de l'agent Classeur, après son ajout dans LibreAgent, quand l'application ou le moteur est absent, quand une mise à jour du plugin vient d'arriver, ou quand le moteur répond par une erreur d'accès au disque, de Codex ou de clé Jev.
---

# Installer Classeur

Classeur fonctionne uniquement sur un Mac où Apple Mail est configuré et associé à LibreAgent (LibreAgent Connect). Le dossier de l'agent (clone du dépôt) contient l'application SwiftUI (`app/`), le moteur Python (`engine/`) et `build.sh`. L'installation place le moteur dans `~/Library/Application Support/Classeur/moteur` et l'application dans `~/Applications/Classeur.app`.

La personne n'ouvre jamais le Terminal. Tu exécutes les commandes ; elle agit seulement dans les fenêtres de macOS, de Classeur et de LibreAgent. Montre le résultat réel de chaque étape et arrête-toi avec la cause exacte au premier échec.

## 1. Vérifier l'ordinateur

1. `uname -s` doit répondre `Darwin`. Sur un autre système, y compris un ordinateur distant Linux de LibreAgent, arrête-toi : « Classeur a besoin d'un Mac avec Apple Mail. Installez l'agent sur ce Mac depuis LibreAgent. »
2. `test -x ~/.local/bin/libreagent-connect` : sans LibreAgent Connect, Classeur ne reçoit pas sa clé Jev. Demande d'associer ce Mac dans LibreAgent (menu Ordinateurs).
3. `xcrun swift --version` : sans réponse, lance `xcode-select --install` et attends que la personne valide la fenêtre d'installation de macOS.
4. `command -v uv` : sans réponse, installe-le avec `brew install uv` si Homebrew est présent ; sinon, donne le lien https://docs.astral.sh/uv/ et arrête-toi.

## 2. Construire et installer

Depuis la racine du dossier de l'agent : `./build.sh`. Le script crée une identité de signature locale propre à ce Mac pour que macOS garde les autorisations d'une version à l'autre, installe le moteur puis l'application. Vérifie que `~/Library/Application\ Support/Classeur/moteur/bin/classeur config` renvoie un événement `config` et que `~/Applications/Classeur.app` existe.

## 3. Clé Jev

La clé Jev se saisit dans LibreAgent, jamais dans la conversation ni dans un fichier. Appelle `agent_secrets_status` pour l'agent Classeur. Si `TYPESAFE_API_KEY` vaut `missing`, donne `configureUrl` : la page ouvre la console TypeSafe pour créer la clé, la reçoit dans un champ masqué, et laisse la personne choisir de la garder pour elle ou de la partager avec les utilisateurs de l'agent. Refuse toute clé collée dans la conversation.

## 4. Ouvrir Classeur

`open ~/Applications/Classeur.app`. Au premier lancement, Classeur affiche sa configuration en quatre étapes, qui se valident seules : accès complet au disque pour lire les mails, accord pour piloter Mail, connexion de Codex au compte ChatGPT, vérification de la clé Jev auprès de LibreAgent. Accompagne la personne jusqu'à « Commencer » ; la configuration reste accessible par le menu Classeur > Autorisations et clé Jev.

## Mise à jour

Quand le plugin Classeur change de version, mets à jour le dossier de l'agent (`git pull --ff-only`), relance `./build.sh`, puis ouvre Classeur. Les autorisations macOS restent valables grâce à l'identité de signature locale.
