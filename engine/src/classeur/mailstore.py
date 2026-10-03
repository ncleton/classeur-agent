"""Accès à Apple Mail via le serveur MCP apple-mailbox-mcp (parasxos/apple-mail-mcp).

Lecture : index SQLite de Mail, en lecture seule.
Rangement : plans de tri relus, appliqués puis vérifiés par le serveur.
"""
from __future__ import annotations

import json
import os
import sys
from contextlib import AsyncExitStack
from dataclasses import dataclass
from pathlib import Path

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

INBOX_NAMES = {"inbox", "boîte de réception", "boite de reception"}


class MailStoreError(RuntimeError):
    def __init__(self, message: str, code: str = "mail_error"):
        super().__init__(message)
        self.code = code


@dataclass
class Inbox:
    account: str
    name: str
    unread: int
    total: int


def _server_command() -> str:
    candidate = Path(sys.executable).parent / "apple-mail-mcp"
    if not candidate.exists():
        raise MailStoreError(
            f"Le serveur apple-mail-mcp est introuvable à côté de {sys.executable}. "
            "Lance « uv sync » dans le dossier engine.",
            code="server_missing",
        )
    return str(candidate)


class MailStore:
    def __init__(self, triage_max: int = 200):
        self._stack = AsyncExitStack()
        self._session: ClientSession | None = None
        self._triage_max = triage_max

    async def __aenter__(self) -> "MailStore":
        env = dict(os.environ)
        env["EMAIL_MCP_TRIAGE_MAX"] = str(max(200, self._triage_max))
        env["EMAIL_MCP_TRIAGE_TTL"] = "1800"
        params = StdioServerParameters(command=_server_command(), args=[], env=env)
        read, write = await self._stack.enter_async_context(stdio_client(params))
        self._session = await self._stack.enter_async_context(ClientSession(read, write))
        await self._session.initialize()
        return self

    async def __aexit__(self, *exc) -> None:
        await self._stack.aclose()

    async def call(self, tool: str, args: dict) -> dict:
        assert self._session is not None
        result = await self._session.call_tool(tool, args)
        data = result.structured_content
        if data is None:
            text = "".join(getattr(part, "text", "") for part in result.content)
            try:
                data = json.loads(text)
            except json.JSONDecodeError as exc:
                raise MailStoreError(f"{tool} a renvoyé une réponse illisible : {text[:300]}") from exc
        if isinstance(data, dict) and data.get("ok") is False:
            code = str(data.get("code") or "mail_error")
            message = data.get("error") or data.get("message") or json.dumps(data, ensure_ascii=False)[:400]
            if "Full Disk Access" in str(message):
                raise MailStoreError(
                    "Classeur ne peut pas lire la base d'Apple Mail. Ouvre Réglages Système > "
                    "Confidentialité et sécurité > Accès complet au disque, active Classeur, "
                    "puis quitte et relance l'application.",
                    code="acces_disque",
                )
            if "-10000" in str(message) and tool in {"mailbox_create", "triage_apply"}:
                raise MailStoreError(
                    "Apple Mail refuse de créer ou de remplir les dossiers : ton compte est probablement déconnecté. "
                    "Dans Mail, ouvre Fenêtre > Diagnostic de connexion. Si iCloud (ou un autre compte) est en rouge, "
                    "reconnecte-le dans Réglages Système, puis relance le traitement.",
                    code="compte_deconnecte",
                )
            raise MailStoreError(f"{tool} : {message}", code=code)
        return data

    async def inboxes(self) -> list[Inbox]:
        data = await self.call("list_mailboxes", {})
        found = [
            Inbox(
                account=item["account"],
                name=item["name"],
                unread=int(item.get("unread") or 0),
                total=int(item.get("total") or 0),
            )
            for item in data.get("mailboxes", [])
            if str(item.get("name", "")).strip().casefold() in INBOX_NAMES
        ]
        if not found:
            raise MailStoreError(
                "Aucune boîte de réception trouvée dans Apple Mail. "
                "Vérifie qu'au moins un compte est configuré et synchronisé dans Mail.",
                code="no_inbox",
            )
        return found

    async def list_messages(self, inbox: Inbox, unread_only: bool, limit: int) -> list[dict]:
        messages: list[dict] = []
        offset = 0
        page = 50
        while len(messages) < limit:
            data = await self.call("search_emails", {
                "mailbox": inbox.name,
                "account": inbox.account,
                "unread_only": unread_only,
                "limit": min(page, limit - len(messages)),
                "offset": offset,
            })
            results = data.get("results") or []
            messages.extend(results)
            if len(results) < page:
                break
            offset += len(results)
        return messages[:limit]

    async def full_messages(self, ids: list[str]) -> dict[str, dict]:
        out: dict[str, dict] = {}
        for start in range(0, len(ids), 20):
            chunk = ids[start:start + 20]
            data = await self.call("get_emails_batch", {"ids": chunk, "view": "full"})
            for email in data.get("emails", []):
                out[str(email["ref"]["id"])] = email
            for error in data.get("errors", []) or []:
                raise MailStoreError(
                    f"Lecture impossible du mail {error.get('id')} : {error.get('error')}",
                    code=str(error.get("code") or "read_failed"),
                )
        return out

    async def history(self, address: str, exclude_id: str) -> list[dict]:
        """Derniers échanges avec cette adresse, reçus et envoyés, pour contextualiser la réponse."""
        if not address:
            return []
        seen: list[dict] = []
        for key, sens in (("from_addr", "reçu"), ("to_addr", "envoyé")):
            data = await self.call("search_emails", {key: address, "limit": 4})
            for item in data.get("results") or []:
                if str(item.get("id")) == exclude_id:
                    continue
                seen.append({
                    "sens": sens,
                    "date": str(item.get("date", ""))[:10],
                    "objet": item.get("subject", ""),
                    "apercu": (item.get("snippet") or "")[:280],
                })
        seen.sort(key=lambda entry: entry["date"], reverse=True)
        return seen[:5]

    async def ensure_folder(self, account: str, path: str) -> None:
        await self.call("mailbox_create", {"account": account, "path": path})

    async def file_messages(
        self,
        *,
        inbox: Inbox,
        unread_only: bool,
        ids: list[str],
        window: int,
        folder: str,
        mark_read: bool,
    ) -> dict:
        """Déplace exactement ids vers folder via un plan relu puis appliqué.

        Le plan reprend le filtre de la lecture (boîte, non lus, les « window » plus récents),
        puis exclut tout ce qui n'appartient pas à ids. Les filtres de date ne sont pas utilisés :
        apple-mailbox-mcp 1.8.2 échoue à enregistrer un plan qui en contient.
        """
        actions = [{"action": "move_to", "mailbox": folder}]
        if mark_read:
            actions.append({"action": "mark_read"})
        plan = await self.call("triage_plan", {
            "mailbox": inbox.name,
            "account": inbox.account,
            "unread_only": unread_only,
            "limit": window,
            "actions": actions,
        })
        planned = [str(item["id"]) for item in plan.get("messages", [])]
        wanted = set(ids)
        missing = sorted(wanted - set(planned))
        if missing:
            raise MailStoreError(
                f"{len(missing)} mail(s) ont quitté la boîte de réception pendant l'analyse "
                f"({', '.join(missing[:5])}). Relance le traitement.",
                code="selection_changed",
            )
        exclude = [message_id for message_id in planned if message_id not in wanted]
        result = await self.call("triage_apply", {
            "plan_id": plan["plan_id"],
            "exclude_ids": exclude or None,
        })
        return result
