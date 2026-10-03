"""Mémoire des mails traités : un mail déjà analysé n'est jamais réanalysé."""
from __future__ import annotations

import json
from datetime import datetime, timezone

from .config import APP_DIR

MEMORY_PATH = APP_DIR / "memoire.json"


def cle(mail: dict) -> str:
    """Clé stable : le Message-ID survit aux déplacements, contrairement à l'identifiant local de Mail."""
    message_id = str(mail.get("message_id") or "").strip().strip("<>")
    if message_id:
        return message_id
    return f"{mail.get('compte', '')}:{mail.get('id', '')}"


def load() -> dict:
    if not MEMORY_PATH.exists():
        return {}
    return json.loads(MEMORY_PATH.read_text(encoding="utf-8"))


def save(memory: dict) -> None:
    MEMORY_PATH.parent.mkdir(parents=True, exist_ok=True)
    tmp = MEMORY_PATH.with_suffix(".tmp")
    tmp.write_text(json.dumps(memory, ensure_ascii=False), encoding="utf-8")
    tmp.replace(MEMORY_PATH)


def remember(cards: list[dict], run_id: str, range_: bool) -> None:
    memory = load()
    now = datetime.now(timezone.utc).isoformat()
    for card in cards:
        key = cle(card)
        previous = memory.get(key, {})
        memory[key] = {
            "carte": card,
            "run": run_id,
            "range": bool(range_ or previous.get("range")),
            "traite_le": previous.get("traite_le", now),
            "maj_le": now,
        }
    save(memory)


def update(card: dict, **fields) -> None:
    memory = load()
    key = cle(card)
    entry = memory.get(key, {"carte": card, "traite_le": datetime.now(timezone.utc).isoformat()})
    entry["carte"] = {**entry.get("carte", {}), **card}
    entry.update(fields)
    entry["maj_le"] = datetime.now(timezone.utc).isoformat()
    memory[key] = entry
    save(memory)


def mark_deleted(mail: dict) -> None:
    update({**mail, "statut": "supprime"}, supprime=True)


def counts() -> dict:
    memory = load()
    return {
        "deja_traites": sum(1 for e in memory.values() if not e.get("supprime")),
        "supprimes": sum(1 for e in memory.values() if e.get("supprime")),
    }
