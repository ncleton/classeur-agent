"""Orchestration : découvrir les classeurs, reclasser l'échantillon, traiter la boîte, valider les réponses."""
from __future__ import annotations

import asyncio
import json
import re
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

from . import ai, jev, mailapp, memoire, ontology
from .ai import clean_body
from .config import RUNS_DIR, Config, typesafe_key
from .mailstore import Inbox, MailStore
from .ontology import A_VERIFIER


def emit(event: str, **data) -> None:
    line = json.dumps({"event": event, **data}, ensure_ascii=False)
    # Ces caractères sont valides en JSON mais certains lecteurs ligne à ligne les prennent pour des fins de ligne.
    line = line.replace("\u2028", "\\u2028").replace("\u2029", "\\u2029").replace("\u0085", "\\u0085")
    sys.stdout.write(line + "\n")
    sys.stdout.flush()


def now_id() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def _address(value: str) -> str:
    match = re.search(r"<([^>]+)>", value)
    return (match.group(1) if match else value).strip()


def _mail(email: dict, inbox: Inbox) -> dict:
    ref = email["ref"]
    return {
        "id": str(ref["id"]),
        "de": ref.get("from_addr", ""),
        "a": ref.get("to", []),
        "objet": ref.get("subject", ""),
        "date": ref.get("date", ""),
        "apercu": (ref.get("snippet") or "")[:160],
        "texte": (email.get("body_text") or ref.get("snippet") or "").strip(),
        "pieces": [a.get("name") or a.get("filename") for a in email.get("attachments") or []],
        "message_id": (email.get("headers") or {}).get("Message-ID", ""),
        "compte": inbox.account,
        "boite": inbox.name,
    }


def _public(mail: dict) -> dict:
    return {k: mail.get(k, "") for k in ("id", "de", "objet", "date", "apercu", "message_id")}


async def _collect(store: MailStore, unread_only: bool, limit: int) -> list[dict]:
    listed: list[tuple[Inbox, dict]] = []
    for inbox in await store.inboxes():
        remaining = limit - len(listed)
        if remaining <= 0:
            break
        for ref in await store.list_messages(inbox, unread_only, remaining):
            listed.append((inbox, ref))
    listed.sort(key=lambda pair: pair[1].get("date", ""), reverse=True)
    listed = listed[:limit]
    if not listed:
        return []
    full = await store.full_messages([str(ref["id"]) for _, ref in listed])
    return [_mail(full[str(ref["id"])], inbox) for inbox, ref in listed]


async def _owner(config: Config, mails: list[dict]) -> str:
    if config.nom:
        return config.nom
    return await asyncio.to_thread(mailapp.owner_name, mails[0]["compte"])


async def _classify(mails: list[dict], onto: dict, config: Config, owner: str) -> dict[str, dict]:
    """Classe chaque mail et émet un événement « classe » dès qu'une décision arrive."""
    async def on_result(mail_id: str, result: dict) -> None:
        emit("classe", id=mail_id, classeur=_effective(result), suggestion=result["classeur"],
             confiance=result["confiance"], incertain=result["incertain"])

    if config.moteur == "jev":
        key = typesafe_key()
        owner_label = owner or "le destinataire"
        return await jev.classify_many(mails, onto, key, owner_label, config.seuil_confiance,
                                       config.appels_en_parallele, on_result)
    results: dict[str, dict] = {}
    batches = [mails[i:i + config.mails_par_lot] for i in range(0, len(mails), config.mails_par_lot)]
    gate = asyncio.Semaphore(config.lots_en_parallele)

    async def run(batch: list[dict]) -> None:
        async with gate:
            items = await ai.enrich(batch, None, onto, config, owner)
        for item in items:
            result = {"classeur": item["classeur"], "confiance": None, "probabilites": {},
                      "incertain": item["classeur"] == A_VERIFIER}
            results[item["id"]] = result
            await on_result(item["id"], result)

    await asyncio.gather(*(run(b) for b in batches))
    return results


def _effective(result: dict) -> str:
    return A_VERIFIER if result["incertain"] else result["classeur"]


# ---------------------------------------------------------------- Découverte

async def decouvrir(config: Config, taille: int | None) -> None:
    n = taille or config.echantillon
    emit("phase", phase="lecture", etape="decouverte")
    async with MailStore(triage_max=n + 50) as store:
        mails = await _collect(store, unread_only=False, limit=n)
    if len(mails) < 5:
        raise ontology.OntologyError(
            f"Ta boîte de réception ne contient que {len(mails)} mail(s) : il en faut au moins 5 pour imaginer des classeurs.",
            code="echantillon_trop_petit",
        )
    for mail in mails:
        mail["texte"] = clean_body(mail["texte"], 1500)
    owner = await _owner(config, mails)
    emit("debut", total=len(mails), proprietaire=owner, mails=[_public(m) for m in mails])

    emit("phase", phase="imagination")
    proposal = await ai.imagine_ontology(mails, config, owner)
    onto = ontology.save(proposal)
    emit("ontologie", classeurs=onto["classeurs"], version=onto["version"])

    emit("phase", phase="classement")
    results = await _classify(mails, onto, config, owner)
    sample = {
        "cree_le": now_id(),
        "proprietaire": owner,
        "version_ontologie": onto["version"],
        "mails": [{k: m[k] for k in ("id", "de", "a", "objet", "date", "apercu", "texte", "pieces", "message_id", "compte", "boite")} for m in mails],
        "affectations": {mid: {**r, "classeur": _effective(r), "suggestion": r["classeur"]} for mid, r in results.items()},
    }
    ontology.save_sample(sample)
    emit("termine", etape="decouverte", total=len(mails), compteurs=dict(Counter(_effective(r) for r in results.values())))


async def reclasser(config: Config) -> None:
    onto = ontology.require()
    sample = ontology.load_sample()
    if not sample:
        raise ontology.OntologyError("Aucun échantillon enregistré. Relance la découverte.", code="echantillon_absent")
    mails = sample["mails"]
    emit("phase", phase="classement", etape="reclassement")
    manuels = {mid: a for mid, a in (sample.get("affectations") or {}).items() if a.get("manuel")}
    results = await _classify(mails, onto, config, sample.get("proprietaire", config.nom))
    sample["affectations"] = {mid: {**r, "classeur": _effective(r), "suggestion": r["classeur"]} for mid, r in results.items()}
    sample["affectations"].update(manuels)
    for mid, a in manuels.items():
        emit("classe", id=mid, classeur=a["classeur"], suggestion=a.get("suggestion"), confiance=a.get("confiance"), incertain=False, manuel=True)
    sample["version_ontologie"] = onto["version"]
    ontology.save_sample(sample)
    emit("termine", etape="reclassement", total=len(mails), compteurs=dict(Counter(a["classeur"] for a in sample["affectations"].values())))


def corriger(mail_id: str, classeur_id: str) -> dict:
    """Correction manuelle d'un mail de l'échantillon : elle survit aux reclassements."""
    onto = ontology.require()
    if classeur_id != A_VERIFIER and classeur_id not in ontology.by_id(onto):
        raise ontology.OntologyError(f"Classeur inconnu : {classeur_id}.")
    sample = ontology.load_sample()
    if not sample or not any(m["id"] == mail_id for m in sample["mails"]):
        raise KeyError(f"Le mail {mail_id} ne fait pas partie de l'échantillon.")
    previous = (sample.get("affectations") or {}).get(mail_id, {})
    affectation = {
        "classeur": classeur_id,
        "suggestion": previous.get("suggestion"),
        "confiance": previous.get("confiance"),
        "probabilites": previous.get("probabilites", {}),
        "incertain": False,
        "manuel": True,
    }
    sample.setdefault("affectations", {})[mail_id] = affectation
    ontology.save_sample(sample)
    return affectation


async def _completer_message_ids(sample: dict) -> None:
    """Ajoute le Message-ID aux mails d'un échantillon enregistré avant qu'il soit conservé."""
    manquants = [m["id"] for m in sample["mails"] if not m.get("message_id") or not m.get("compte")]
    if not manquants:
        return
    trouves: dict[str, dict] = {}
    async with MailStore() as store:
        for start in range(0, len(manquants), 20):
            data = await store.call("get_emails_batch", {"ids": manquants[start:start + 20], "view": "metadata"})
            for e in data.get("emails", []):
                trouves[str(e["ref"]["id"])] = {
                    "message_id": (e.get("headers") or {}).get("Message-ID", ""),
                    "compte": e["ref"].get("account", ""),
                    "boite": e["ref"].get("mailbox", ""),
                }
    for mail in sample["mails"]:
        found = trouves.get(mail["id"])
        if found:
            for key, value in found.items():
                if value and not mail.get(key):
                    mail[key] = value
    ontology.save_sample(sample)


async def etat_ontologie() -> dict:
    onto = ontology.load()
    sample = ontology.load_sample()
    if sample:
        await _completer_message_ids(sample)
    return {
        "classeurs": onto["classeurs"] if onto else [],
        "version": onto.get("version") if onto else None,
        "echantillon": [_public(m) for m in sample["mails"]] if sample else [],
        "affectations": sample.get("affectations", {}) if sample else {},
        "version_echantillon": sample.get("version_ontologie") if sample else None,
    }


# ---------------------------------------------------------------- Traitement

def run_path(run_id: str) -> Path:
    return RUNS_DIR / f"{run_id}.json"


def save_run(run: dict) -> None:
    RUNS_DIR.mkdir(parents=True, exist_ok=True)
    path = run_path(run["id"])
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(run, ensure_ascii=False, indent=1), encoding="utf-8")
    tmp.replace(path)


def load_run(run_id: str) -> dict:
    path = run_path(run_id)
    if not path.exists():
        raise FileNotFoundError(f"Traitement {run_id} introuvable dans {RUNS_DIR}.")
    return json.loads(path.read_text(encoding="utf-8"))


def latest_run() -> dict | None:
    if not RUNS_DIR.exists():
        return None
    files = sorted(RUNS_DIR.glob("*.json"))
    for path in reversed(files):
        run = json.loads(path.read_text(encoding="utf-8"))
        if run.get("format") == 2:
            return run
    return None


def headline(urgent: int, verifier: int) -> str:
    if urgent:
        return f"{urgent} mail{'s' if urgent > 1 else ''} demande{'nt' if urgent > 1 else ''} ton attention aujourd'hui. Le reste a une place."
    if verifier:
        return f"Rien d'urgent. {verifier} mail{'s' if verifier > 1 else ''} à vérifier, tout le reste a une place."
    return "Rien d'urgent qui t'attend. Tout a une place."


async def traiter(config: Config, *, ranger: bool, portee: str | None, limite: int | None, retraiter: bool = False) -> dict:
    onto = ontology.require()
    classeurs = ontology.by_id(onto)
    mode = portee or config.portee
    max_count = limite or config.limite
    unread_only = mode == "non_lus"
    run_id = now_id()
    emit("phase", phase="connexion", run_id=run_id)

    async with MailStore(triage_max=max_count + 50) as store:
        mails = await _collect(store, unread_only, max_count)
        memory = memoire.load()
        supprimes = [m for m in mails if memory.get(memoire.cle(m), {}).get("supprime")]
        mails = [m for m in mails if not memory.get(memoire.cle(m), {}).get("supprime")]
        connus: dict[str, dict] = {}
        if not retraiter:
            for m in mails:
                carte = (memory.get(memoire.cle(m)) or {}).get("carte")
                if carte and (carte.get("classeur") == A_VERIFIER or carte.get("classeur") in classeurs):
                    connus[m["id"]] = carte
        nouveaux = [m for m in mails if m["id"] not in connus]
        if not mails:
            run = {"format": 2, "id": run_id, "portee": mode, "range": ranger, "total": 0, "mails": [],
                   "compteurs": {}, "titre": "Ta boîte est déjà vide.", "classeurs": onto["classeurs"]}
            save_run(run)
            emit("termine", run=run)
            return run
        owner = await _owner(config, mails)
        emit("debut", total=len(mails), proprietaire=owner, repris=len(connus), ignores=len(supprimes),
             mails=[_public(m) for m in mails])
        for mail in nouveaux:
            mail["historique"] = await store.history(_address(mail["de"]), mail["id"])

        cards: dict[str, dict] = {}
        done = 0
        for m in mails:
            if m["id"] not in connus:
                continue
            ancienne = connus[m["id"]]
            c = classeurs.get(ancienne["classeur"])
            card = {
                **ancienne,
                "id": m["id"], "compte": m["compte"], "boite": m["boite"],
                "message_id": m["message_id"], "texte": m["texte"],
                "dossier": config.folder_path(c["dossier"]) if c else "",
                "action": c["action"] if c else A_VERIFIER,
            }
            cards[m["id"]] = card
            done += 1
            emit("mail", lus=done, total=len(mails), deja=True, mail={k: v for k, v in card.items() if k != "texte"})

        results = await _classify(nouveaux, onto, config, owner) if nouveaux else {}
        assigned = {mid: _effective(r) for mid, r in results.items()}

        batches = [nouveaux[i:i + config.mails_par_lot] for i in range(0, len(nouveaux), config.mails_par_lot)]
        gate = asyncio.Semaphore(config.lots_en_parallele)

        async def run_batch(batch: list[dict]) -> None:
            nonlocal done
            async with gate:
                items = await ai.enrich(batch, assigned, onto, config, owner)
            for item in items:
                mail = next(m for m in batch if m["id"] == item["id"])
                cid = assigned[mail["id"]]
                c = classeurs.get(cid)
                action = c["action"] if c else A_VERIFIER
                result = results[mail["id"]]
                card = {
                    "id": mail["id"], "classeur": cid, "action": action,
                    "suggestion": result["classeur"], "confiance": result["confiance"],
                    "expediteur": item["expediteur"], "objet_court": item["objet_court"], "ligne": item["ligne"],
                    "etiquette": item["etiquette"], "urgent": bool(item["urgent"]),
                    "reponse": item.get("reponse", "") if action == "repondre" else "",
                    "statut": {"repondre": "a_valider", "transferer": "a_valider", A_VERIFIER: "a_verifier"}.get(action, "fait"),
                    "dossier": config.folder_path(c["dossier"]) if c else "",
                    "transfert_email": c.get("transfert_email", "") if c else "",
                    "compte": mail["compte"], "boite": mail["boite"], "message_id": mail["message_id"],
                    "de": mail["de"], "a": mail["a"], "date": mail["date"], "objet": mail["objet"], "texte": mail["texte"],
                }
                cards[mail["id"]] = card
                done += 1
                emit("mail", lus=done, total=len(mails), mail={k: v for k, v in card.items() if k != "texte"})

        await asyncio.gather(*(run_batch(b) for b in batches))
        ordered = [cards[m["id"]] for m in mails]
        counts = Counter(card["classeur"] for card in ordered)
        title = headline(sum(1 for c in ordered if c["urgent"]), counts.get(A_VERIFIER, 0))
        emit("compris", compteurs=dict(counts), titre=title)
        run = {"format": 2, "id": run_id, "portee": mode, "range": ranger, "proprietaire": owner,
               "total": len(ordered), "mails": ordered, "compteurs": dict(counts), "titre": title,
               "classeurs": onto["classeurs"]}
        save_run(run)
        memoire.remember(ordered, run_id, False)

        if ranger:
            emit("phase", phase="rangement")
            per_inbox = Counter((c["compte"], c["boite"]) for c in ordered)
            groups: dict[tuple[str, str, str], list[dict]] = defaultdict(list)
            for card in ordered:
                if card["classeur"] != A_VERIFIER:
                    groups[(card["compte"], card["boite"], card["classeur"])].append(card)
            created: set[tuple[str, str]] = set()
            inboxes = {(i.account, i.name): i for i in await store.inboxes()}
            for c in onto["classeurs"]:
                for (account, box, cid), items in groups.items():
                    if cid != c["id"]:
                        continue
                    folder = config.folder_path(c["dossier"])
                    if (account, folder) not in created:
                        await store.ensure_folder(account, folder)
                        created.add((account, folder))
                    if c["action"] == "transferer" and c.get("transfert_auto"):
                        for card in items:
                            await asyncio.to_thread(mailapp.forward, account=account, mailboxes=[box],
                                                    message_id=card["message_id"], recipient=c["transfert_email"])
                            card["statut"] = "transfere"
                            emit("transfert", id=card["id"], statut="transfere")
                    await store.file_messages(
                        inbox=inboxes[(account, box)], unread_only=unread_only,
                        ids=[card["id"] for card in items], window=per_inbox[(account, box)] + 20,
                        folder=folder, mark_read=c["action"] != "repondre",
                    )
                    emit("range", classeur=cid, nombre=len(items), dossier=folder)
            save_run(run)
            memoire.remember(ordered, run_id, True)

        emit("termine", run=run)
        return run


async def compter() -> dict:
    async with MailStore() as store:
        inboxes = await store.inboxes()
    return {"non_lus": sum(i.unread for i in inboxes), "total": sum(i.total for i in inboxes), **memoire.counts()}


def _find(run: dict, mail_id: str) -> dict:
    for item in run["mails"]:
        if item["id"] == mail_id:
            return item
    raise KeyError(f"Le mail {mail_id} ne fait pas partie du traitement {run['id']}.")


def envoyer(run_id: str, mail_id: str, body: str) -> dict:
    run = load_run(run_id)
    item = _find(run, mail_id)
    if item["action"] != "repondre":
        raise ValueError("Ce mail n'attend pas de réponse.")
    if item["statut"] == "envoye":
        raise ValueError("Cette réponse a déjà été envoyée.")
    if not body.strip():
        raise ValueError("La réponse est vide.")
    original = {"ref": {"date": item["date"], "from_addr": item["de"]}, "body_text": item["texte"]}
    mailbox_candidates = [m for m in (item["dossier"], item["boite"]) if m]
    mailapp.send_reply(account=item["compte"], mailboxes=mailbox_candidates,
                       message_id=item["message_id"], body=body, original=original)
    item["reponse"] = body
    item["statut"] = "envoye"
    item["envoye_le"] = datetime.now(timezone.utc).isoformat()
    save_run(run)
    memoire.update({k: v for k, v in item.items()})
    return item


def transferer(run_id: str, mail_id: str) -> dict:
    run = load_run(run_id)
    item = _find(run, mail_id)
    if item["action"] != "transferer" or "@" not in item.get("transfert_email", ""):
        raise ValueError("Aucun destinataire de transfert valide pour ce mail.")
    mailbox_candidates = [m for m in (item["dossier"], item["boite"]) if m]
    mailapp.forward(account=item["compte"], mailboxes=mailbox_candidates,
                    message_id=item["message_id"], recipient=item["transfert_email"])
    item["statut"] = "transfere"
    save_run(run)
    memoire.update({k: v for k, v in item.items()})
    return item


def ouvrir_reponse(run_id: str, mail_id: str) -> dict:
    """Ouvre la réponse préparée dans la fenêtre de rédaction d'Apple Mail, pour la relire et l'envoyer depuis Mail."""
    run = load_run(run_id)
    item = _find(run, mail_id)
    if item["action"] != "repondre" or not item.get("reponse", "").strip():
        raise ValueError("Aucune réponse préparée pour ce mail.")
    original = {"ref": {"date": item["date"], "from_addr": item["de"]}, "body_text": item.get("texte", "")}
    candidates = [m for m in (item.get("dossier"), item["boite"]) if m]
    mailapp.compose_reply(account=item["compte"], mailboxes=candidates, message_id=item["message_id"],
                          body=item["reponse"], original=original)
    return item


async def deplacer(run_id: str, mail_id: str, classeur_id: str, config: Config) -> dict:
    """Déplace un mail traité vers un autre classeur, dans Classeur et, si le traitement a rangé, dans Apple Mail."""
    run = load_run(run_id)
    card = _find(run, mail_id)
    onto = ontology.require()
    classeurs = ontology.by_id(onto)
    if classeur_id != A_VERIFIER and classeur_id not in classeurs:
        raise ontology.OntologyError(f"Classeur inconnu : {classeur_id}.")
    if card["classeur"] == classeur_id:
        return card
    if card.get("statut") in {"envoye", "transfere"}:
        raise ValueError("Ce mail a déjà été envoyé ou transféré : il ne peut plus changer de classeur.")
    cible = classeurs.get(classeur_id)
    nouveau_dossier = config.folder_path(cible["dossier"]) if cible else ""
    if run.get("range"):
        source = [m for m in (card.get("dossier"), card["boite"]) if m]
        destination = nouveau_dossier or card["boite"]
        if nouveau_dossier:
            async with MailStore() as store:
                await store.ensure_folder(card["compte"], nouveau_dossier)
        await asyncio.to_thread(mailapp.move, account=card["compte"], mailboxes=source,
                                message_id=card["message_id"], target=destination)
    action = cible["action"] if cible else A_VERIFIER
    card.update({
        "classeur": classeur_id,
        "action": action,
        "dossier": nouveau_dossier,
        "transfert_email": cible.get("transfert_email", "") if cible else "",
        "statut": {"repondre": "a_valider", "transferer": "a_valider", A_VERIFIER: "a_verifier"}.get(action, "fait"),
        "manuel": True,
    })
    if action == "repondre" and not card.get("reponse"):
        mail = {k: card[k] for k in ("id", "de", "a", "objet", "date")}
        mail.update({"texte": card.get("texte", ""), "pieces": [], "historique": []})
        items = await ai.enrich([mail], {mail_id: classeur_id}, onto, config, run.get("proprietaire") or config.nom)
        card["reponse"] = items[0].get("reponse", "")
        card["ligne"] = items[0]["ligne"]
        card["etiquette"] = items[0]["etiquette"]
    run["compteurs"] = dict(Counter(c["classeur"] for c in run["mails"]))
    save_run(run)
    memoire.update({k: v for k, v in card.items()}, range=bool(run.get("range")))
    return card


async def supprimer(mail_id: str, run_id: str | None, config: Config) -> dict:
    """Place un mail dans la corbeille d'Apple Mail et l'oublie définitivement dans Classeur."""
    onto = ontology.load() or {"classeurs": []}
    dossiers = [config.folder_path(c["dossier"]) for c in onto["classeurs"]]
    sample = None
    run = None
    if run_id:
        run = load_run(run_id)
        cible = _find(run, mail_id)
        candidates = [m for m in (cible.get("dossier"), cible.get("boite")) if m]
    else:
        sample = ontology.load_sample()
        if not sample:
            raise ontology.OntologyError("Aucun échantillon enregistré.", code="echantillon_absent")
        await _completer_message_ids(sample)
        cible = next((m for m in sample["mails"] if m["id"] == mail_id), None)
        if cible is None:
            raise KeyError(f"Le mail {mail_id} ne fait pas partie de l'échantillon.")
        candidates = [cible.get("boite") or "INBOX"]
    if not cible.get("message_id") or not cible.get("compte"):
        raise ValueError("Apple Mail ne fournit pas l'identifiant de ce mail : supprime-le directement dans Mail.")
    candidates += [d for d in dossiers if d not in candidates]
    await asyncio.to_thread(mailapp.delete, account=cible["compte"], mailboxes=candidates, message_id=cible["message_id"])
    memoire.mark_deleted(cible)
    if run is not None:
        cible["statut"] = "supprime"
        save_run(run)
    else:
        sample["mails"] = [m for m in sample["mails"] if m["id"] != mail_id]
        sample.get("affectations", {}).pop(mail_id, None)
        ontology.save_sample(sample)
    return {"id": mail_id}
