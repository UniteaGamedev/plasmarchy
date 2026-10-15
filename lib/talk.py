#!/usr/bin/python3 -I
"""Conversation mode: talk to your computer via a hotkey or wake word.

Flow: listen until a speech pause -> AI answer (short, meant to be spoken) -> read aloud -> keep listening for
FOLLOW_UP seconds for follow-up questions -> otherwise end. Meanwhile talk.qml shows the state at the bottom.
Pressing the hotkey again (second call) sends the utterance right away once you have spoken; before that, or
while the answer is being read, it ends the session. Saying "stop"/"thanks" (also German) ends it as well.
The microphone is only open during a session.
"""
import base64
import json
import os
import re
import signal
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import assistant  # noqa: E402
import voice      # noqa: E402
from i18n import tr  # noqa: E402

RUN = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
STATUS = os.path.join(RUN, "plasmarchy-talk.json")
PIDFILE = os.path.join(RUN, "plasmarchy-talk.pid")
LIB = os.path.dirname(os.path.realpath(__file__))
FOLLOW_UP = float(voice.conf().get("FOLLOW_UP", "8") or 8)
STOP_WORDS = re.compile(r"\b(stopp?|ende|beenden|abbrechen|danke|das war'?s|tschüss|goodbye|thanks?|thank you)\b", re.I)


def is_stop(text):
    """A short utterance containing a stop word ("okay thanks", "stop please", "danke schön") ends the session."""
    return len(re.findall(r"\w+", text)) <= 4 and bool(STOP_WORDS.search(text))

overlay = None
stopping = False
state = "listening"


def hotkey():
    return voice.conf().get("HOTKEY", "Meta+Shift+Space")


def status(new_state, user="", answer="", note=""):
    global state
    state = new_state
    hint = tr("Press {0} again to send", hotkey()) if new_state == "listening" else ""
    tmp = STATUS + ".tmp"
    json.dump({"state": new_state, "user": user, "answer": answer, "note": note, "hint": hint},
              open(tmp, "w"), ensure_ascii=False)
    os.replace(tmp, STATUS)


def stop(*_):
    global stopping
    stopping = True
    voice.stop_speaking()          # also ends ongoing listening


def hotkey_again(*_):
    """Hotkey pressed during a session: send what was said so far, otherwise end the session."""
    if state == "listening" and voice.LISTEN["started"]:
        voice.LISTEN["send"] = True
    else:
        stop()


def start_overlay(colors):
    env = dict(os.environ, QML_XHR_ALLOW_FILE_READ="1", QT_FORCE_STDERR_LOGGING="1")
    proc = subprocess.Popen(["/usr/lib/qt6/bin/qml", os.path.join(LIB, "talk.qml"), "--", STATUS, colors],
                            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True, env=env)

    def watch():                   # a stop request from the overlay ends the session
        for line in proc.stderr:
            if "PLASMARCHY_TALK=stop" in line:
                os.kill(os.getpid(), signal.SIGTERM)
    import threading
    threading.Thread(target=watch, daemon=True).start()
    return proc


def theme_colors():
    out = os.path.join(RUN, "plasmarchy-talk-colors.json")
    try:
        import tomllib
        from plasmarchy_common import theme_dir
        state = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
                             "plasmarchy", "current")
        slug = open(state).readline().strip() or "osaka-jade"
        c = tomllib.load(open(os.path.join(theme_dir(slug), "colors.toml"), "rb"))
        json.dump({k: c.get(k, "#888888") for k in ("background", "foreground", "accent", "muted")}, open(out, "w"))
    except Exception:
        json.dump({"background": "#111111", "foreground": "#dddddd", "accent": "#88aaff", "muted": "#666666"},
                  open(out, "w"))
    return out


def main():
    global overlay
    # A second call (hotkey pressed again) is passed on to the running session
    try:
        other = int(open(PIDFILE).read())
        # only signal it if the stored PID really is a running conversation session
        if b"talk.py" in open(f"/proc/{other}/cmdline", "rb").read():
            os.kill(other, signal.SIGUSR1)
            return
    except (OSError, ValueError):
        pass
    open(PIDFILE, "w").write(str(os.getpid()))
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGUSR1, hotkey_again)
    signal.signal(signal.SIGINT, stop)
    st = voice.status()
    status("listening")
    overlay = start_overlay(theme_colors())
    server = voice.server_start()   # loads the recognition model while the user speaks
    try:
        if not st["stt"]:
            status("error", note=tr("Voice isn't set up yet. In a terminal: {0}", "plasmarchy voice setup"))
            subprocess.run(["sleep", "4"])
            return
        first, new = True, False
        while not stopping:
            status("listening")
            heard = voice.listen(max_wait=30.0 if first else FOLLOW_UP)
            if stopping or heard.get("timeout"):
                break
            if "error" in heard:
                status("listening", note=heard["error"])
                continue
            text = heard["text"]
            if is_stop(text):
                break
            status("thinking", user=text)
            res = assistant.ask(text, new=new, voice=True)
            answer = res.get("answer") or res.get("error", "")
            note = res.get("notice", "")
            status("speaking", user=text, answer=answer, note=note)
            if not stopping and st["tts"]:
                voice.speak(base64.b64encode(((note + " ") if note else "").encode() + answer.encode()).decode(),
                            wait=True)
            first = False
    finally:
        status("done")
        voice.server_stop(server)
        voice.stop_speaking()
        try:
            os.remove(PIDFILE)
        except OSError:
            pass
        subprocess.run(["sleep", "0.4"])
        if overlay:
            overlay.terminate()


if __name__ == "__main__":
    main()
