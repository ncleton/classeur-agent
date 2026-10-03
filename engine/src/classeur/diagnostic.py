"""État des prérequis de Classeur sur ce Mac, pour l'écran de configuration de l'application."""
from __future__ import annotations

import subprocess
from pathlib import Path

from .config import which

MAIL_DIR = Path.home() / "Library" / "Mail"


def _mail() -> dict:
    """Le dossier de Mail n'est lisible qu'avec l'accès complet au disque de l'application qui lance le moteur."""
    try:
        versions = [entry for entry in MAIL_DIR.iterdir() if entry.name.startswith("V")]
    except PermissionError:
        return {"lisible": False, "comptes": False}
    except FileNotFoundError:
        return {"lisible": True, "comptes": False}
    comptes = any((version / "MailData" / "Envelope Index").exists() for version in versions)
    return {"lisible": True, "comptes": comptes}


def _codex() -> dict:
    chemin = which("codex")
    if not chemin:
        return {"installe": False, "connecte": False, "chemin": None, "detail": ""}
    try:
        proc = subprocess.run([chemin, "login", "status"], capture_output=True, text=True, timeout=20)
    except subprocess.TimeoutExpired:
        return {"installe": True, "connecte": False, "chemin": chemin, "detail": "codex login status ne répond pas."}
    detail = (proc.stdout or proc.stderr).strip().splitlines()
    return {"installe": True, "connecte": proc.returncode == 0, "chemin": chemin, "detail": detail[0][:200] if detail else ""}


def etat() -> dict:
    return {"acces_mail": _mail(), "codex": _codex()}
