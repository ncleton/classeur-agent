# Classeur

Classeur lit les mails d'Apple Mail, comprend ce que chacun demande, les range dans des classeurs et prépare les réponses, que la personne valide avant envoi. Il s'exécute uniquement sur le Mac de la personne.

## Organisation

- `app/` : application SwiftUI (interface, menu du Dock, validation et envoi).
- `engine/` : moteur Python, commande `classeur` ; il pilote apple-mail-mcp, classe par Jev (TypeSafe) ou Codex, rédige par Codex CLI ou l'API OpenAI.
- `build.sh` : construit et installe le moteur et l'application.
- `plugins/classeur/` : plugin Codex et Claude Code de l'agent, avec les skills `installer-classeur` et `utiliser-classeur`.
- `.agents/plugins/marketplace.json` et `.claude-plugin/marketplace.json` : catalogues lus par Codex, Claude Code et LibreAgent.
- `scripts/export-agent.sh` : produit le dépôt public de l'agent à partir de la version commitée.

## Règles

- Aucune réponse, aucun transfert ni aucune suppression sans validation explicite de la personne.
- Les mails restent sur le Mac : ne jamais copier leur contenu, des adresses ou des captures dans Git, la mémoire partagée de l'agent ou un service externe autre que le modèle qui les analyse.
- La clé Jev (TypeSafe) se saisit dans LibreAgent pendant l'onboarding de l'agent (`plugins/classeur/libreagent.json`) ; la personne choisit de la garder pour elle ou de la partager avec les utilisateurs de l'agent. Classeur la reçoit par `libreagent-connect secrets exec` : ne jamais l'écrire sur le disque, dans le dépôt ni dans une conversation.
- La personne ne passe jamais par le Terminal : les autorisations macOS se donnent dans l'écran de configuration de l'application.
- Les captures de `docs/` contiennent de vrais mails : elles ne sortent jamais de ce dépôt privé. Le dépôt public se produit uniquement par `scripts/export-agent.sh`.
- Toute erreur doit remonter avec sa cause et la correction à faire, sans mode dégradé.
- Augmenter la version dans les deux manifestes du plugin à chaque publication.
