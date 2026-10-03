"""Actions qui passent par Mail.app : nom du compte, réponse et transfert."""
from __future__ import annotations

import subprocess

from .maildiag import refus_mail

SCRIPT = r'''
on findMessage(acctId, boxNames, mid)
	tell application "Mail"
		set acct to first account whose id is acctId
		repeat with boxName in boxNames
			set boxText to boxName as text
			if boxText is not "" then
				try
					set mb to mailbox boxText of acct
					set hits to (messages of mb whose message id is mid)
					if (count of hits) > 0 then return item 1 of hits
				end try
			end if
		end repeat
	end tell
	error "Le mail d'origine est introuvable dans Apple Mail." number 1001
end findMessage

on run argv
	set action to item 1 of argv
	set acctId to item 2 of argv
	if action is "owner" then
		tell application "Mail"
			set acct to first account whose id is acctId
			return full name of acct
		end tell
	end if
	set boxNames to paragraphs of (item 3 of argv)
	set mid to item 4 of argv
	set bodyText to item 5 of argv
	set recipientAddress to item 6 of argv
	set theMsg to my findMessage(acctId, boxNames, mid)
	tell application "Mail"
		if action is "reply" then
			set outgoing to reply theMsg without opening window
			delay 0.3
			set content of outgoing to bodyText
		else if action is "forward" then
			set outgoing to forward theMsg without opening window
			delay 0.3
			tell outgoing to make new to recipient at end of to recipients with properties {address:recipientAddress}
		else if action is "move" then
			set acct to first account whose id is acctId
			move theMsg to mailbox recipientAddress of acct
			return "moved"
		else if action is "delete" then
			delete theMsg
			return "deleted"
		else if action is "compose" then
			set outgoing to reply theMsg with opening window
			delay 0.4
			set content of outgoing to bodyText
			activate
			return "composed"
		else
			error "Action inconnue : " & action number 1002
		end if
		delay 0.3
		set wasSent to send outgoing
		if wasSent is false then error "Mail a refusé l'envoi." number 1003
	end tell
	return "sent"
end run
'''


class MailAppError(RuntimeError):
    pass


def _run(args: list[str], timeout: int = 90) -> str:
    try:
        proc = subprocess.run(
            ["/usr/bin/osascript", "-", *args],
            input=SCRIPT,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as exc:
        raise MailAppError(
            "Mail.app ne répond pas. Si macOS affiche une demande d'autorisation, accepte-la "
            "(Réglages Système > Confidentialité et sécurité > Automatisation > Mail)."
        ) from exc
    if proc.returncode != 0:
        detail = proc.stderr.strip()
        if "-1743" in detail:
            raise MailAppError(
                "Classeur n'a pas le droit de piloter Mail. Active-le dans Réglages Système > "
                "Confidentialité et sécurité > Automatisation > Classeur > Mail."
            )
        if "-10000" in detail:
            raise MailAppError(refus_mail(detail)[0])
        if "(1001)" in detail:
            raise MailAppError(
                "Ce mail n'est plus dans ta boîte de réception ni dans tes dossiers Classeur : il a sans doute "
                "déjà été supprimé ou déplacé dans Apple Mail."
            )
        raise MailAppError(f"Mail.app a renvoyé une erreur : {detail}")
    return proc.stdout.strip()


def owner_name(account: str) -> str:
    return _run(["owner", account], timeout=30)


def _quote(original: dict) -> str:
    ref = original["ref"]
    lines = (original.get("body_text") or "").strip().splitlines()
    quoted = "\n".join(f"> {line}" for line in lines[:200])
    return f"\n\nLe {ref.get('date', '')[:16].replace('T', ' à ')}, {ref.get('from_addr', '')} a écrit :\n{quoted}"


def send_reply(*, account: str, mailboxes: list[str], message_id: str, body: str, original: dict) -> None:
    _run(["reply", account, "\n".join(mailboxes), message_id.strip("<>"), body + _quote(original), ""])


def forward(*, account: str, mailboxes: list[str], message_id: str, recipient: str) -> None:
    _run(["forward", account, "\n".join(mailboxes), message_id.strip("<>"), "", recipient])


def move(*, account: str, mailboxes: list[str], message_id: str, target: str) -> None:
    _run(["move", account, "\n".join(mailboxes), message_id.strip("<>"), "", target])


def delete(*, account: str, mailboxes: list[str], message_id: str) -> None:
    """Place le mail dans la corbeille d'Apple Mail (il reste récupérable)."""
    _run(["delete", account, "\n".join(mailboxes), message_id.strip("<>"), "", ""])


def compose_reply(*, account: str, mailboxes: list[str], message_id: str, body: str, original: dict) -> None:
    """Ouvre la fenêtre de réponse d'Apple Mail, pré-remplie avec la réponse préparée. Rien n'est envoyé."""
    _run(["compose", account, "\n".join(mailboxes), message_id.strip("<>"), body + _quote(original), ""])
