"""Ligne de commande de Classeur. Chaque commande écrit des événements JSON, un par ligne."""
from __future__ import annotations

import argparse
import asyncio
import json
import sys

from . import config as cfg
from . import ontology, runner


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="classeur")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("decouvrir", help="Imaginer les classeurs à partir d'un échantillon de mails.")
    p.add_argument("--echantillon", type=int)
    sub.add_parser("reclasser", help="Reclasser l'échantillon avec les classeurs actuels.")
    p = sub.add_parser("ontologie", help="Afficher les classeurs, ou les enregistrer (JSON sur l'entrée standard).")
    p.add_argument("--enregistrer", action="store_true")

    p = sub.add_parser("traiter", help="Lire, classer, ranger et préparer les réponses.")
    p.add_argument("--sans-rangement", action="store_true")
    p.add_argument("--retraiter", action="store_true", help="Réanalyser aussi les mails déjà traités.")
    p.add_argument("--portee", choices=["non_lus", "boite"])
    p.add_argument("--limite", type=int)

    p = sub.add_parser("envoyer", help="Envoyer une réponse validée (corps sur l'entrée standard).")
    p.add_argument("--run", required=True)
    p.add_argument("--mail", required=True)
    p = sub.add_parser("transferer", help="Transférer un mail au destinataire du classeur.")
    p.add_argument("--run", required=True)
    p.add_argument("--mail", required=True)
    p = sub.add_parser("corriger", help="Corriger à la main le classeur d'un mail de l'échantillon.")
    p.add_argument("--mail", required=True)
    p.add_argument("--classeur", required=True)
    p = sub.add_parser("deplacer", help="Déplacer un mail traité vers un autre classeur.")
    p.add_argument("--run", required=True)
    p.add_argument("--mail", required=True)
    p.add_argument("--classeur", required=True)
    p = sub.add_parser("supprimer", help="Placer un mail dans la corbeille d'Apple Mail.")
    p.add_argument("--mail", required=True)
    p.add_argument("--run")

    sub.add_parser("dernier", help="Afficher le dernier traitement.")
    sub.add_parser("compter", help="Compter les mails des boîtes de réception.")
    sub.add_parser("config", help="Créer la configuration si besoin et afficher son chemin.")

    args = parser.parse_args(argv)
    try:
        if args.cmd == "config":
            runner.emit("config", chemin=str(cfg.ensure_config()))
        elif args.cmd == "dernier":
            runner.emit("dernier", run=runner.latest_run())
        elif args.cmd == "ontologie":
            if args.enregistrer:
                ontology.save(json.loads(sys.stdin.read()))
            runner.emit("ontologie", **asyncio.run(runner.etat_ontologie()))
        elif args.cmd == "corriger":
            runner.emit("corrige", id=args.mail, **runner.corriger(args.mail, args.classeur))
        else:
            conf = cfg.load()
            if args.cmd == "compter":
                runner.emit("compte", **asyncio.run(runner.compter()))
            elif args.cmd == "decouvrir":
                asyncio.run(runner.decouvrir(conf, args.echantillon))
            elif args.cmd == "reclasser":
                asyncio.run(runner.reclasser(conf))
            elif args.cmd == "traiter":
                asyncio.run(runner.traiter(conf, ranger=not args.sans_rangement, portee=args.portee,
                                           limite=args.limite, retraiter=args.retraiter))
            elif args.cmd == "envoyer":
                item = runner.envoyer(args.run, args.mail, sys.stdin.read())
                runner.emit("envoye", id=item["id"], a=item["de"], le=item["envoye_le"])
            elif args.cmd == "transferer":
                item = runner.transferer(args.run, args.mail)
                runner.emit("transfere", id=item["id"], vers=item["transfert_email"])
            elif args.cmd == "deplacer":
                card = asyncio.run(runner.deplacer(args.run, args.mail, args.classeur, conf))
                runner.emit("deplace", mail={k: v for k, v in card.items() if k != "texte"})
            elif args.cmd == "supprimer":
                runner.emit("supprime", **asyncio.run(runner.supprimer(args.mail, args.run, conf)))
        return 0
    except BaseExceptionGroup as group:
        first = group.exceptions[0]
        while isinstance(first, BaseExceptionGroup):
            first = first.exceptions[0]
        return _fail(first)
    except Exception as exc:  # noqa: BLE001 - chaque erreur devient un événement lisible par l'application
        return _fail(exc)


def _fail(exc: BaseException) -> int:
    message = exc.args[0] if exc.args else str(exc)
    runner.emit("erreur", message=str(message) or type(exc).__name__, code=str(getattr(exc, "code", type(exc).__name__)))
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
