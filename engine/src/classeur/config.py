"""Configuration de Classeur, lue dans ~/Library/Application Support/Classeur/config.toml."""
from __future__ import annotations

import os
import shutil
import tomllib
from dataclasses import dataclass
from pathlib import Path

APP_DIR = Path(os.environ.get(
    "CLASSEUR_HOME",
    Path.home() / "Library" / "Application Support" / "Classeur",
))
CONFIG_PATH = APP_DIR / "config.toml"
RUNS_DIR = APP_DIR / "runs"

DEFAULT_CONFIG = """# Configuration de Classeur.
# Les classeurs (colonnes) se règlent dans l'application.

[identite]
# Nom utilisé pour signer les réponses. Vide : nom complet du compte Apple Mail.
nom = ""
# Signature ajoutée à la fin de chaque réponse.
signature = ""
# Ce que fait ton activité, pour que les réponses soient justes.
contexte = ""
ton = "Reprendre le tutoiement ou le vouvoiement de l'expéditeur. Phrases courtes, chaleureuses, sans formule creuse."

[classement]
# "jev" : modèle de décision TypeSafe, avec la clé Jev enregistrée dans LibreAgent.
# "codex" : Codex choisit le classeur en même temps qu'il rédige.
moteur = "jev"
appels_en_parallele = 6
# En dessous de cette confiance, le mail est marqué « à vérifier ».
seuil_confiance = 0.5

[redaction]
# "codex" utilise ta connexion ChatGPT via Codex CLI ; "openai" utilise OPENAI_API_KEY.
fournisseur = "codex"
modele = ""
mails_par_lot = 8
lots_en_parallele = 6

[portee]
# "boite" : tous les mails des boîtes de réception ; "non_lus" : seulement les non lus.
mode = "boite"
limite = 200

[decouverte]
# Nombre de mails lus pour imaginer tes classeurs au premier lancement.
echantillon = 100

[dossiers]
# Dossier parent créé dans chaque compte Apple Mail.
parent = "Classeur"
"""


class ConfigError(RuntimeError):
    def __init__(self, message: str, code: str = "configuration"):
        super().__init__(message)
        self.code = code


@dataclass
class Config:
    nom: str
    signature: str
    contexte: str
    ton: str
    moteur: str
    appels_en_parallele: int
    seuil_confiance: float
    fournisseur: str
    modele: str
    mails_par_lot: int
    lots_en_parallele: int
    portee: str
    limite: int
    echantillon: int
    parent: str

    def folder_path(self, dossier: str) -> str:
        return f"{self.parent}/{dossier}" if self.parent else dossier


def ensure_config() -> Path:
    APP_DIR.mkdir(parents=True, exist_ok=True)
    RUNS_DIR.mkdir(parents=True, exist_ok=True)
    if not CONFIG_PATH.exists():
        CONFIG_PATH.write_text(DEFAULT_CONFIG, encoding="utf-8")
    return CONFIG_PATH


def _choice(value: str, allowed: set[str], key: str) -> str:
    if value not in allowed:
        raise ConfigError(f"{key} = {value!r} est inconnu. Valeurs possibles : {', '.join(sorted(allowed))} ({CONFIG_PATH}).")
    return value


def load() -> Config:
    ensure_config()
    try:
        raw = tomllib.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    except tomllib.TOMLDecodeError as exc:
        raise ConfigError(f"Le fichier {CONFIG_PATH} est invalide : {exc}") from exc
    ident = raw.get("identite", {})
    classement = raw.get("classement", {})
    redaction = raw.get("redaction") or raw.get("ia", {})
    portee = raw.get("portee", {})
    decouverte = raw.get("decouverte", {})
    dossiers = raw.get("dossiers", {})
    return Config(
        nom=str(ident.get("nom", "")).strip(),
        signature=str(ident.get("signature", "")).strip(),
        contexte=str(ident.get("contexte", "")).strip(),
        ton=str(ident.get("ton", "")).strip(),
        moteur=_choice(str(classement.get("moteur", "jev")).strip(), {"jev", "codex"}, "[classement] moteur"),
        appels_en_parallele=max(1, min(12, int(classement.get("appels_en_parallele", 6)))),
        seuil_confiance=float(classement.get("seuil_confiance", 0.5)),
        fournisseur=_choice(str(redaction.get("fournisseur", "codex")).strip(), {"codex", "openai"}, "[redaction] fournisseur"),
        modele=str(redaction.get("modele", "")).strip(),
        mails_par_lot=max(1, int(redaction.get("mails_par_lot", 8))),
        lots_en_parallele=max(1, int(redaction.get("lots_en_parallele", 6))),
        portee=_choice(str(portee.get("mode", "boite")).strip(), {"boite", "non_lus"}, "[portee] mode"),
        limite=max(1, int(portee.get("limite", 200))),
        echantillon=max(10, min(200, int(decouverte.get("echantillon", 100)))),
        parent=str(dossiers.get("parent", "Classeur")).strip().strip("/"),
    )


def typesafe_key() -> str:
    """Clé Jev transmise par LibreAgent Connect (`secrets exec`) au lancement du moteur."""
    env = os.environ.get("TYPESAFE_API_KEY", "").strip()
    if env:
        return env
    raise ConfigError(
        "Clé Jev absente : Classeur la reçoit de LibreAgent au lancement du classement. Lance le classement "
        "depuis l'application Classeur sur un Mac associé à LibreAgent, et enregistre ta clé Jev dans "
        "LibreAgent (agent Classeur, page Clés).",
        code="cle_typesafe",
    )


SEARCH_PATH = [
    "/opt/homebrew/bin",
    "/usr/local/bin",
    str(Path.home() / ".local" / "bin"),
    "/usr/bin",
    "/bin",
]


def which(binary: str) -> str | None:
    found = shutil.which(binary)
    if found:
        return found
    for folder in SEARCH_PATH:
        candidate = Path(folder) / binary
        if candidate.exists() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None
