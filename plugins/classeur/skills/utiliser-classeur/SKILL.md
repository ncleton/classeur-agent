---
name: utiliser-classeur
description: Trier les mails d'Apple Mail avec Classeur, analyser une boîte sans rien déplacer, consulter le dernier traitement, déplacer ou corriger le classement d'un mail, et envoyer ou transférer une réponse après validation explicite. Utiliser quand la personne demande de traiter, trier, ranger ou classer ses mails, de préparer ses réponses, ou de voir ce que Classeur a fait.
---

# Utiliser Classeur

Le moteur est `~/Library/Application Support/Classeur/moteur/bin/classeur` (appelé `classeur` ci-dessous). Chaque commande écrit des événements JSON, un par ligne ; un événement `erreur` porte `message` et `code`. S'il manque, applique le skill installer-classeur. Les traitements sont enregistrés dans `~/Library/Application Support/Classeur/runs/`.

L'application `~/Applications/Classeur.app` reste l'interface principale pour relire et valider les réponses. Propose-la quand la personne préfère cliquer.

## Commandes

| Besoin | Commande |
|---|---|
| Compter les mails des boîtes de réception | `classeur compter` |
| Analyser sans rien déplacer | `classeur traiter --sans-rangement --portee boite --limite 20` |
| Traiter et ranger | `classeur traiter` (options : `--portee non_lus` ou `boite`, `--limite N`, `--retraiter`) |
| Voir le dernier traitement | `classeur dernier` |
| Voir ou enregistrer les classeurs | `classeur ontologie`, `classeur ontologie --enregistrer` (JSON sur l'entrée standard) |
| Proposer des classeurs | `classeur decouvrir --echantillon 100`, puis `classeur reclasser` |
| Corriger le classeur d'un mail de l'échantillon | `classeur corriger --mail <id> --classeur <classeur>` |
| Déplacer un mail traité | `classeur deplacer --run <run> --mail <id> --classeur <classeur>` |
| Envoyer une réponse validée | corps sur l'entrée standard de `classeur envoyer --run <run> --mail <id>` |
| Transférer | `classeur transferer --run <run> --mail <id>` |
| Mettre à la corbeille | `classeur supprimer --mail <id> [--run <run>]` |

## Règles

- Pour une première utilisation ou une demande vague, commence par une analyse sans rangement et présente le résultat par classeur avant de proposer `classeur traiter`.
- Aucune réponse ne part sans validation. Montre le texte exact, le destinataire et l'objet, puis n'appelle `classeur envoyer` qu'après un accord explicite sur ce texte. Si la personne modifie la réponse, envoie le texte modifié.
- `transferer` et `supprimer` demandent aussi une confirmation explicite, mail par mail.
- Résume les mails sans recopier leur contenu complet. Ne copie jamais un mail, une adresse ou une pièce jointe hors de ce Mac, et n'écris rien de tel dans la mémoire partagée de l'agent.
- Rapporte chaque erreur avec son message ; ne remplace jamais un résultat du moteur par une estimation.
