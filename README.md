# Classeur

Classeur lit les mails d'Apple Mail, comprend ce que chacun demande, les range dans des dossiers et prépare les réponses. Tu relis chaque réponse, tu la modifies si besoin, et Mail l'envoie dans le bon fil de discussion.

L'expérience reprend le reel « AI Operator » : un clic sur « Traiter tous mes mails » (fenêtre ou menu du Dock), l'écran « Je lis tes mails », la synthèse « Compris. », le rangement en colonnes, puis la validation des réponses.

## Démarrage rapide

    ./build.sh
    open build/Classeur.app

Au premier lancement :

1. Ouvre Réglages Système > Confidentialité et sécurité > Accès complet au disque, ajoute **Classeur**, puis relance l'application. C'est ce qui permet de lire la base locale d'Apple Mail.
2. Au premier envoi, accepte la demande « Classeur souhaite contrôler Mail ».
3. Connecte Codex CLI à ton compte ChatGPT si ce n'est pas déjà fait : \`codex login\`.
4. Renseigne ton nom, ta signature et ton activité via le menu Classeur > Ouvrir la configuration… (fichier \`~/Library/Application Support/Classeur/config.toml\`).

## Comment ça marche

| Brique | Rôle |
|---|---|
| [parasxos/apple-mail-mcp](https://github.com/parasxos/apple-mail-mcp) 1.8.2 (MIT) | Lecture rapide de l'index d'Apple Mail, création des dossiers, rangement par plan relu, appliqué puis vérifié. |
| \`engine/\` (Python) | Pilote ce serveur MCP, fait comprendre chaque mail par l'IA (Codex CLI ou API OpenAI), range, transfère, enregistre chaque traitement. |
| \`app/\` (SwiftUI) | Interface, menu du Dock, validation et envoi des réponses. |
| Mail.app (AppleScript) | Envoi des réponses validées et des transferts, depuis le compte qui a reçu le mail. |

Catégories : À répondre, À transférer (seulement si des contacts sont configurés), Factures, Devis, Archivés. Les dossiers sont créés sous \`Classeur/\` dans chaque compte concerné.

Aucune réponse ne part sans validation. Un transfert part seul uniquement si le contact est marqué \`automatique = true\`.

## Moteur en ligne de commande

    cd engine
    uv sync
    .venv/bin/classeur traiter --sans-rangement --portee boite --limite 10   # analyse sans rien déplacer
    .venv/bin/classeur traiter                                               # traitement complet
    .venv/bin/classeur compter
    .venv/bin/classeur dernier

Chaque commande écrit des événements JSON, un par ligne. Les traitements sont enregistrés dans \`~/Library/Application Support/Classeur/runs/\`.

## Captures des écrans

Le test de rendu affiche les vrais écrans hors écran à partir d'un traitement enregistré :

    cd app
    CLASSEUR_SNAPSHOT_RUN=<run.json> CLASSEUR_SNAPSHOT_OUT=/tmp/classeur-snaps swift test


## Agent LibreAgent

Classeur est aussi un agent LibreAgent, Codex et Claude Code. Le plugin `plugins/classeur` apporte deux skills : `installer-classeur` construit l'application et le moteur sur le Mac et guide les autorisations, `utiliser-classeur` pilote le moteur et n'envoie rien sans validation.

Une entreprise équipée de LibreAgent ajoute l'agent depuis son lien public (Ajouter un agent), choisit qui l'utilise, et peut désigner un consultant externe qui l'administrera depuis son propre serveur LibreAgent. L'agent s'installe uniquement sur un Mac où Apple Mail est configuré.
