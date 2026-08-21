#!/usr/bin/env python3
"""citrix-drive.py — pilote l'installateur interactif Citrix (setupwfc/hinst)
en répondant à chaque invite RECONNUE par son texte, au lieu d'une séquence
de réponses aveugle.

Pourquoi : setupwfc n'a pas de mode silencieux, et l'ordre/le nombre de ses
questions change d'une version à l'autre (26.04 demande le répertoire AVANT
toute confirmation, puis enchaîne USB, EPA, App Protection, FIDO2…). Une
séquence figée « 1 y ␤ y y n 3 » installait dans un répertoire nommé « y »
puis abandonnait — constaté sur matériel réel le 2026-08-21.

Usage : citrix-drive.py /chemin/vers/setupwfc [--log FICHIER]
Sortie : 0 si l'installateur s'est terminé normalement, ≠0 sinon.
Uniquement la bibliothèque standard (pty) : rien à installer.
"""
import os
import pty
import re
import select
import sys
import time

# Règles (motif sur la FIN du flux de sortie, insensible à la casse) → réponse.
# L'ordre compte : la première règle qui correspond gagne.
RULES = [
    # Menu principal : installer la première fois, quitter ensuite.
    (r"Enter option number", "MENU"),
    # Répertoire d'installation : défaut (/opt/Citrix/ICAClient).
    (r"directory in which .* is to be installed", ""),
    (r"Do you want to create it\?", "y"),
    (r"Proceed with installation\?", "y"),
    (r"Re-installing will overwrite.*Do you want to proceed\?", "y"),
    (r"Do you want to proceed\?", "y"),
    (r"prerequisites required for installation is not present.*proceed", "y"),
    # Intégrations bureau : oui (fichiers .desktop, types MIME, GStreamer).
    (r"integrate .* with CDE\?", "y"),
    (r"GStreamer .* use the plugin", "y"),
    (r"Found GStreamer entry", "y"),
    (r"integrate .*(KDE|GNOME|desktop)", "y"),
    # USB : oui (redirection de périphériques dans les sessions ICA).
    (r"install USB support\?", "y"),
    # Composants indésirables sur ce poste : EPA, App Protection (noyau +
    # incompatible Wayland/xwayland-satellite), FIDO2 HID bridge.
    (r"install EPA\?", "n"),
    (r"app protection component", "n"),
    (r"FIDO2 HID Bridge", "n"),
    # Relance après réponse incomprise : on retombe sur le défaut proposé.
    (r"You must answer yes or no.*\[default (y|yes)\]", "y"),
    (r"You must answer yes or no.*\[default (n|no)\]", "n"),
    # Filets génériques : suivre le défaut affiché.
    (r"\[default (y|yes)\]\s*:?\s*$", "y"),
    (r"\[default (n|no)\]\s*:?\s*$", "n"),
    (r"press (enter|return)", ""),
]
PROMPT_TAIL = re.compile(r"[:?\]]\s*$")
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    setup = sys.argv[1]
    logf = None
    if "--log" in sys.argv:
        logf = open(sys.argv[sys.argv.index("--log") + 1], "a", encoding="utf-8")

    def log(msg: str) -> None:
        line = f"[citrix-drive] {msg}"
        print(line, file=sys.stderr, flush=True)
        if logf:
            logf.write(line + "\n")
            logf.flush()

    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(os.path.dirname(os.path.abspath(setup)))
        os.execv(os.path.abspath(setup), [os.path.abspath(setup)])

    buf = ""
    menu_seen = 0
    last_answer_at = 0.0
    idle_since = time.monotonic()
    invalid = 0
    rc = 1
    try:
        while True:
            r, _, _ = select.select([fd], [], [], 1.0)
            if fd in r:
                try:
                    data = os.read(fd, 4096)
                except OSError:
                    break
                if not data:
                    break
                text = ANSI.sub("", data.decode("utf-8", "replace"))
                sys.stdout.write(text)
                sys.stdout.flush()
                if logf:
                    logf.write(text)
                buf = (buf + text)[-4000:]
                idle_since = time.monotonic()
                if "Invalid Entry" in text:
                    invalid += 1
                    if invalid >= 3:
                        log("l'installateur rejette nos réponses (Invalid Entry ×3) — abandon")
                        os.write(fd, b"3\n")
                        break
                continue

            # Silence d'au moins 1 s : l'installateur attend probablement.
            tail = buf.replace("\r", "")[-600:]
            if not PROMPT_TAIL.search(tail) or time.monotonic() - last_answer_at < 0.3:
                if time.monotonic() - idle_since > 900:
                    log("aucune activité depuis 15 min — abandon")
                    break
                continue
            answer = None
            for pattern, reply in RULES:
                if re.search(pattern, tail, re.IGNORECASE | re.DOTALL):
                    if reply == "MENU":
                        menu_seen += 1
                        reply = "1" if menu_seen == 1 else "3"
                    answer = (pattern, reply)
                    break
            if answer is None:
                if time.monotonic() - idle_since > 120:
                    log("invite non reconnue, aucune règle ne correspond — abandon :\n" + tail[-300:])
                    break
                continue
            log(f"invite « …{tail.strip()[-70:]} » → réponse « {answer[1]} »")
            os.write(fd, (answer[1] + "\n").encode())
            last_answer_at = time.monotonic()
            buf = ""  # ne pas ré-appliquer la même règle sur le même texte
    finally:
        try:
            _, status = os.waitpid(pid, 0)
            rc = os.waitstatus_to_exitcode(status)
        except ChildProcessError:
            pass
        log(f"setupwfc terminé, code {rc}")
        if logf:
            logf.close()
    return rc


if __name__ == "__main__":
    sys.exit(main())
