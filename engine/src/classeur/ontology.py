"""Ontologie de classement : chaque classeur est un concept défini, avec ses critères et son action."""
from __future__ import annotations

import json
import re
import unicodedata
from datetime import datetime, timezone

from .config import APP_DIR

ONTOLOGY_PATH = APP_DIR / "ontologie.json"
SAMPLE_PATH = APP_DIR / "echantillon.json"

ACTIONS = ("repondre", "transferer", "ranger", "archiver")
COULEURS = ("violet", "cyan", "ambre", "citron", "bleu", "vert", "rose", "corail")
SYMBOLES = (
    "arrowshape.turn.up.left.fill", "arrowshape.turn.up.right.fill", "doc.text.fill", "signature",
    "archivebox.fill", "person.2.fill", "cart.fill", "calendar", "briefcase.fill", "creditcard.fill",
    "megaphone.fill", "bell.fill", "building.columns.fill", "shippingbox.fill", "star.fill",
    "exclamationmark.bubble.fill", "newspaper.fill", "lock.fill", "wrench.and.screwdriver.fill", "heart.fill",
)
A_VERIFIER = "a_verifier"
MAX_CLASSEURS = 8


class OntologyError(ValueError):
    def __init__(self, message: str, code: str = "ontologie"):
        super().__init__(message)
        self.code = code


def slug(value: str) -> str:
    text = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode().lower()
    text = re.sub(r"[^a-z0-9]+", "_", text).strip("_")
    return (text or "classeur")[:32]


def _lines(value) -> list[str]:
    if isinstance(value, str):
        value = value.splitlines()
    return [str(item).strip() for item in (value or []) if str(item).strip()][:8]


def normalize(raw: dict) -> dict:
    """Valide et normalise une ontologie venant de l'IA ou de l'application."""
    items = raw.get("classeurs")
    if not isinstance(items, list) or not 2 <= len(items) <= MAX_CLASSEURS:
        raise OntologyError(f"Il faut entre 2 et {MAX_CLASSEURS} classeurs.")
    seen: set[str] = set()
    dossiers: set[str] = set()
    out = []
    for item in items:
        nom = str(item.get("nom", "")).strip()
        definition = str(item.get("definition", "")).strip()
        if not nom:
            raise OntologyError("Chaque classeur doit avoir un nom.")
        if not definition:
            raise OntologyError(f"Le classeur « {nom} » n'a pas de définition.")
        ident = slug(str(item.get("id") or nom))
        if ident == A_VERIFIER:
            ident = "classeur_a_verifier"
        base, n = ident, 2
        while ident in seen:
            ident, n = f"{base}_{n}", n + 1
        seen.add(ident)
        action = str(item.get("action", "ranger"))
        if action not in ACTIONS:
            raise OntologyError(f"Action inconnue pour « {nom} » : {action}.")
        dossier = str(item.get("dossier") or nom).strip().replace("/", "-")
        if dossier.casefold() in dossiers:
            raise OntologyError(f"Deux classeurs utilisent le même dossier « {dossier} ».")
        dossiers.add(dossier.casefold())
        email = str(item.get("transfert_email", "")).strip()
        if action == "transferer" and "@" not in email:
            raise OntologyError(f"Le classeur « {nom} » transfère les mails : indique l'adresse du destinataire.")
        couleur = str(item.get("couleur", "violet"))
        symbole = str(item.get("symbole", "archivebox.fill"))
        out.append({
            "id": ident,
            "nom": nom[:40],
            "definition": definition[:600],
            "inclure": _lines(item.get("inclure")),
            "exclure": _lines(item.get("exclure")),
            "exemples": _lines(item.get("exemples")),
            "action": action,
            "dossier": dossier[:60],
            "couleur": couleur if couleur in COULEURS else "violet",
            "symbole": symbole if symbole in SYMBOLES else "archivebox.fill",
            "transfert_email": email,
            "transfert_auto": bool(item.get("transfert_auto", False)) and action == "transferer",
        })
    return {"classeurs": out}


def load() -> dict | None:
    if not ONTOLOGY_PATH.exists():
        return None
    return json.loads(ONTOLOGY_PATH.read_text(encoding="utf-8"))


def require() -> dict:
    onto = load()
    if not onto:
        raise OntologyError(
            "Tes classeurs ne sont pas encore définis. Lance la découverte depuis l'application.",
            code="ontologie_absente",
        )
    return onto


def save(raw: dict) -> dict:
    onto = normalize(raw)
    previous = load() or {}
    now = datetime.now(timezone.utc).isoformat()
    onto["cree_le"] = previous.get("cree_le", now)
    onto["modifie_le"] = now
    onto["version"] = int(previous.get("version", 0)) + 1
    _write(ONTOLOGY_PATH, onto)
    return onto


def by_id(onto: dict) -> dict[str, dict]:
    return {item["id"]: item for item in onto["classeurs"]}


def criteria(onto: dict) -> dict[str, str]:
    out = {}
    for item in onto["classeurs"]:
        parts = [f"{item['nom']}. {item['definition']}"]
        if item["inclure"]:
            parts.append("Y entrent : " + " ; ".join(item["inclure"]) + ".")
        if item["exclure"]:
            parts.append("N'y entrent pas : " + " ; ".join(item["exclure"]) + ".")
        out[item["id"]] = " ".join(parts)[:900]
    out[A_VERIFIER] = "Aucun classeur ne correspond clairement à ce mail, ou les informations ne suffisent pas pour décider."
    return out


def load_sample() -> dict | None:
    if not SAMPLE_PATH.exists():
        return None
    return json.loads(SAMPLE_PATH.read_text(encoding="utf-8"))


def save_sample(sample: dict) -> None:
    _write(SAMPLE_PATH, sample)


def _write(path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    tmp.replace(path)
