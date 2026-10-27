#!/usr/bin/env python3
"""Bot Telegram d'administration GCRV (acces admin uniquement, sans dependance externe)."""
import json
import os
import re
import subprocess
import time
import urllib.parse
import urllib.request

TOKEN = os.environ["BOT_TOKEN"]
ADMIN_ID = int(os.environ["ADMIN_ID"])
GCRV = os.environ.get("GCRV_BIN", "/usr/local/bin/gcrv")
API = f"https://api.telegram.org/bot{TOKEN}/"
ANSI = re.compile(r"\x1b\[[0-9;]*m")
NAME = re.compile(r"^[a-z][a-z0-9-]{0,29}$")
USER = re.compile(r"^[A-Za-z0-9_-]{1,32}$")
DAYS = re.compile(r"^[0-9]{1,4}$")

HELP = (
    "Commandes :\n"
    "/services\n"
    "/create <service> [region]\n"
    "/delservice <service>\n"
    "/adduser <service> <user> [jours]\n"
    "/deluser <service> <user>\n"
    "/users <service>\n"
    "/link <service> <user>\n"
    "/expire"
)


def tg(method, **params):
    data = urllib.parse.urlencode(params).encode()
    with urllib.request.urlopen(API + method, data, timeout=70) as r:
        return json.load(r)


def send(chat, text):
    text = ANSI.sub("", text).strip() or "(vide)"
    for i in range(0, len(text), 3900):
        tg("sendMessage", chat_id=chat, text=text[i:i + 3900])


def run(args):
    try:
        p = subprocess.run([GCRV] + args, capture_output=True, text=True, timeout=1500)
        return (p.stdout + p.stderr)
    except subprocess.TimeoutExpired:
        return "Delai depasse."


def handle(chat, text):
    parts = text.strip().split()
    if not parts or not parts[0].startswith("/"):
        return
    cmd, a = parts[0].split("@")[0].lower(), parts[1:]

    def bad():
        send(chat, "Arguments invalides.\n\n" + HELP)

    if cmd in ("/start", "/help"):
        send(chat, HELP)
    elif cmd == "/services":
        send(chat, run(["service-list"]))
    elif cmd == "/create" and 1 <= len(a) <= 2 and NAME.match(a[0]):
        send(chat, "Creation en cours (2-4 min)...")
        send(chat, run(["service-create"] + a))
    elif cmd == "/delservice" and len(a) == 1 and NAME.match(a[0]):
        send(chat, run(["service-delete", a[0]]))
    elif cmd == "/adduser" and 2 <= len(a) <= 3 and NAME.match(a[0]) and USER.match(a[1]) \
            and (len(a) == 2 or DAYS.match(a[2])):
        send(chat, "Deploiement en cours (2-4 min)...")
        send(chat, run(["user-add"] + a))
    elif cmd == "/deluser" and len(a) == 2 and NAME.match(a[0]) and USER.match(a[1]):
        send(chat, "Deploiement en cours (2-4 min)...")
        send(chat, run(["user-del"] + a))
    elif cmd == "/users" and len(a) == 1 and NAME.match(a[0]):
        send(chat, run(["user-list", a[0]]))
    elif cmd == "/link" and len(a) == 2 and NAME.match(a[0]) and USER.match(a[1]):
        send(chat, run(["link"] + a))
    elif cmd == "/expire":
        send(chat, run(["expire-check"]))
    else:
        bad()


def main():
    offset = 0
    while True:
        try:
            res = tg("getUpdates", offset=offset, timeout=50)
            for u in res.get("result", []):
                offset = u["update_id"] + 1
                m = u.get("message") or {}
                uid = (m.get("from") or {}).get("id")
                if uid != ADMIN_ID:
                    continue  # acces reserve a l'admin
                handle(m["chat"]["id"], m.get("text", ""))
        except Exception as e:  # reseau, JSON, etc.
            print("erreur:", e, flush=True)
            time.sleep(5)


if __name__ == "__main__":
    main()
