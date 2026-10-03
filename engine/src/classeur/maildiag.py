"""Explique un refus d'Apple Mail (erreur AppleScript -10000) à partir du journal système de Mail.

Mail répond -10000 (« Le gestionnaire AppleEvent a échoué ») sans dire pourquoi. Cause fréquente :
le trousseau de session est verrouillé, Mail ne peut plus lire le mot de passe du compte et sa
connexion au serveur reste non authentifiée. Mail l'écrit dans son journal.
"""
from __future__ import annotations

import subprocess

KEYCHAIN_LOCKED = "com.apple.accounts.keychain Code=-25308"

TROUSSEAU_VERROUILLE = (
    "Apple Mail ne peut plus lire le mot de passe de ton compte : le trousseau « session » de macOS "
    "est verrouillé, donc Mail n'arrive pas à se connecter au serveur pour créer ou remplir les dossiers. "
    "Clique sur « Déverrouiller le trousseau », saisis le mot de passe de ta session Mac, puis relance le traitement."
)


def keychain_locked() -> bool | None:
    """True si Mail a signalé un trousseau verrouillé ces 3 dernières minutes, None si le journal est illisible."""
    try:
        proc = subprocess.run(
            [
                "/usr/bin/log", "show", "--last", "3m", "--style", "compact",
                "--predicate", f'process == "Mail" AND eventMessage CONTAINS "{KEYCHAIN_LOCKED}"',
            ],
            capture_output=True,
            text=True,
            timeout=40,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return None
    if proc.returncode != 0:
        return None
    return KEYCHAIN_LOCKED in proc.stdout


def refus_mail(detail: str) -> tuple[str, str]:
    """Message et code d'erreur pour un refus -10000 de Mail."""
    locked = keychain_locked()
    if locked:
        return TROUSSEAU_VERROUILLE, "trousseau_verrouille"
    if locked is None:
        return (
            "Apple Mail a refusé l'opération sans en donner la raison, et Classeur n'a pas pu lire le journal "
            "de Mail pour la trouver. Dans Mail, ouvre Fenêtre > Diagnostic de connexion pour vérifier que "
            f"le compte se connecte, puis relance le traitement. Erreur de Mail : {detail}",
            "mail_refus",
        )
    return (
        "Apple Mail a refusé l'opération sans en donner la raison. Le trousseau est accessible : dans Mail, "
        "ouvre Fenêtre > Diagnostic de connexion pour vérifier que le compte se connecte au serveur, puis "
        f"relance le traitement. Erreur de Mail : {detail}",
        "mail_refus",
    )
