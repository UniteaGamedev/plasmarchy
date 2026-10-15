#!/usr/bin/python3 -I
"""Assistant settings (backend of the settings page in the widget).

  settings.py get                    all settings + option lists as JSON (labels translated)
  settings.py set <KEY> <value>      store; also does follow-up work (download voice/model, wake word service,
                                     change the hotkey in KDE)
  settings.py set64 <KEY> <base64>   same, value base64-encoded (used by the widget)
  settings.py level <source>         microphone level (2 s recording) in dB, for the level meter
  settings.py sample                 play a voice sample
Everything is stored in ~/.config/plasmarchy/assistant.conf.
"""
import json
import os
import re
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import assistant  # noqa: E402
from i18n import tr  # noqa: E402
import voice      # noqa: E402

HOME = os.path.expanduser("~")
LIB = os.path.dirname(os.path.realpath(__file__))
CONF = assistant.CONF
WAKE_ENV = os.path.join(voice.DATA, "wakeenv")
TALK_ACTION = ["plasmarchy-talk.desktop", "_launch", "Talk to your computer", "Talk to your computer"]

VOICES = {
    "en_US-ryan-medium": "Ryan – English (US), male",
    "en_US-amy-medium": "Amy – English (US), female",
    "en_GB-alba-medium": "Alba – English (UK), female",
    "de_DE-thorsten-medium": "Thorsten – German, male",
    "de_DE-thorsten-high": "Thorsten HQ – German, male (more natural, larger)",
    "de_DE-kerstin-low": "Kerstin – German, female",
    "de_DE-ramona-low": "Ramona – German, female",
}
MODELS = {"base": "Fast (base, 142 MB)", "small": "Balanced (small, 466 MB)",
          "medium": "Accurate (medium, 1.5 GB, slower)"}
WAKE_WORDS = {"off": "Off (hotkey only)", "hey_jarvis": "“Hey Jarvis”", "alexa": "“Alexa”",
              "hey_mycroft": "“Hey Mycroft”", "hey_marvin": "“Hey Marvin”"}
KEYS = {"PROVIDER", "PROVIDER_ORDER", "LOCAL_MODEL", "ACTIONS", "SPEAK_ANSWERS", "NOTIFY_LEFT", "VOICE_MODEL",
        "VOICE_TTS", "VOICE_SOURCE", "VOICE_LANG", "WAKE_WORD", "WAKE_SENSITIVITY", "FOLLOW_UP", "HOTKEY"}
DEFAULTS = {"SPEAK_ANSWERS": "off", "NOTIFY_LEFT": "20 5", "WAKE_WORD": "off", "WAKE_SENSITIVITY": "0.5",
            "FOLLOW_UP": "8", "HOTKEY": "Meta+Shift+Space"}


def read_conf():
    c = dict(DEFAULTS)
    c.update(assistant.config())
    c.update({k: v for k, v in voice.conf().items()})
    if os.path.isfile(CONF):
        for line in open(CONF):
            if "=" in line and not line.lstrip().startswith("#"):
                k, v = line.strip().split("=", 1)
                c[k.strip()] = v.strip().strip('"')
    return c


def write_conf(key, value):
    lines = open(CONF).read().splitlines() if os.path.isfile(CONF) else []
    quoted = f'"{value}"' if " " in value else value
    lines = [l for l in lines if not l.strip().startswith(key + "=")] + [f"{key}={quoted}"]
    os.makedirs(os.path.dirname(CONF), exist_ok=True)
    open(CONF, "w").write("\n".join(lines) + "\n")


# --- Hotkey (KDE kglobalaccel) ----------------------------------------------------------------
MODS = {"meta": 0x10000000, "ctrl": 0x04000000, "alt": 0x08000000, "shift": 0x02000000}
NAMED = {"space": 0x20, "return": 0x01000004, "enter": 0x01000005, "tab": 0x01000001, "escape": 0x01000000,
         "pause": 0x01000008, "print": 0x01000009, "home": 0x01000010, "end": 0x01000011}


def key_code(seq):
    """'Meta+Shift+Space' -> Qt key code."""
    code = 0
    for part in seq.split("+"):
        p = part.strip().lower()
        if p in MODS:
            code |= MODS[p]
        elif p in NAMED:
            code |= NAMED[p]
        elif re.fullmatch(r"f([1-9]|1[0-9]|2[0-4])", p):
            code |= 0x01000030 + int(p[1:]) - 1
        elif len(p) == 1 and p.isalnum():
            code |= ord(p.upper())
        else:
            raise SystemExit(tr("Unknown key: {0}", part))
    return code


def set_hotkey(seq):
    code = key_code(seq)
    subprocess.run(["busctl", "--user", "call", "org.kde.kglobalaccel", "/kglobalaccel", "org.kde.KGlobalAccel",
                    "setForeignShortcutKeys", "asa(ai)", "4", *TALK_ACTION, "1", "1", str(code)], check=True,
                   stdout=subprocess.DEVNULL)
    subprocess.run(["kwriteconfig6", "--file", "kglobalshortcutsrc", "--group", "services", "--group",
                    TALK_ACTION[0], "--key", "_launch", seq], check=False)


# --- Wake word --------------------------------------------------------------------------------
def wake_installed():
    return os.path.isfile(os.path.join(WAKE_ENV, "bin", "python")) and subprocess.run(
        [os.path.join(WAKE_ENV, "bin", "python"), "-c", "import openwakeword"], capture_output=True).returncode == 0


def apply_wake(word):
    if word != "off" and not wake_installed():
        subprocess.run([sys.executable, "-m", "venv", WAKE_ENV], check=True)
        subprocess.run([os.path.join(WAKE_ENV, "bin", "pip"), "install", "-q", "openwakeword"], check=True)
    action = ["enable", "--now"] if word != "off" else ["disable", "--now"]
    subprocess.run(["systemctl", "--user", *action, "plasmarchy-wake.service"], capture_output=True)
    if word != "off":   # pick up new settings
        subprocess.run(["systemctl", "--user", "restart", "plasmarchy-wake.service"], capture_output=True)


# --- Queries ----------------------------------------------------------------------------------
def sources():
    out = subprocess.run(["pactl", "-f", "json", "list", "sources"], capture_output=True, text=True).stdout
    try:
        data = json.loads(out)
    except ValueError:
        return []
    return [{"id": s["name"], "name": s.get("description", s["name"])} for s in data
            if ".monitor" not in s["name"]]


def get():
    c = read_conf()
    st = voice.status()
    vdir = os.path.join(voice.DATA, "voices")
    mdir = os.path.join(voice.DATA, "models")
    ollama = assistant.ollama_ok()
    return {
        "provider": c["PROVIDER"], "order": c["PROVIDER_ORDER"].split(), "localModel": c["LOCAL_MODEL"],
        "actions": c["ACTIONS"] == "on", "speakAnswers": c["SPEAK_ANSWERS"] == "on", "notifyLeft": c["NOTIFY_LEFT"],
        "providers": [{"id": p["id"], "name": p["name"]} for p in assistant.available()],
        "allProviders": [{"id": k, "name": tr(v["name"])} for k, v in assistant.PROVIDERS.items()],
        "ollama": {"running": ollama, "modelReady": assistant.ollama_ok(c["LOCAL_MODEL"]),
                   "installed": bool(shutil.which("ollama"))},
        "voice": {"ready": st["stt"], "ttsReady": st["tts"], "model": c["VOICE_MODEL"], "tts": c["VOICE_TTS"],
                  "source": c["VOICE_SOURCE"], "followUp": c["FOLLOW_UP"],
                  "models": [{"id": k, "name": tr(v), "installed": os.path.isfile(os.path.join(mdir, f"ggml-{k}.bin"))}
                             for k, v in MODELS.items()],
                  "voices": [{"id": k, "name": tr(v), "installed": os.path.isfile(os.path.join(vdir, k + ".onnx"))}
                             for k, v in VOICES.items()],
                  "sources": [{"id": "auto", "name": tr("Automatic (microphone with speech signal)")}] + sources()},
        "wake": {"word": c["WAKE_WORD"], "sensitivity": float(c["WAKE_SENSITIVITY"]), "installed": wake_installed(),
                 "running": subprocess.run(["systemctl", "--user", "is-active", "plasmarchy-wake.service"],
                                           capture_output=True, text=True).stdout.strip() == "active",
                 "words": [{"id": k, "name": tr(v)} for k, v in WAKE_WORDS.items()]},
        "hotkey": c["HOTKEY"],
    }


def set_value(key, value):
    if key not in KEYS:
        raise SystemExit(tr("Unknown setting: {0}", key))
    if key == "HOTKEY":
        set_hotkey(value)
    # Download first, store afterwards: an interrupted download keeps the previous, working setting
    if key == "VOICE_TTS" and value in VOICES:
        region, name, quality = value.split("-", 2)
        url = f"{voice.VOICES}/{region.split('_')[0]}/{region}/{name}/{quality}/{value}.onnx"
        dest = os.path.join(voice.DATA, "voices", value + ".onnx")
        voice.download(url, dest)
        voice.download(url + ".json", dest + ".json")
    elif key == "VOICE_MODEL" and value in MODELS:
        voice.download(f"{voice.MODELS}/ggml-{value}.bin", os.path.join(voice.DATA, "models", f"ggml-{value}.bin"))
    write_conf(key, value)
    if key in ("WAKE_WORD", "WAKE_SENSITIVITY", "VOICE_SOURCE"):
        apply_wake(read_conf()["WAKE_WORD"])
    return {"ok": True}


def level(source):
    wav = os.path.join(voice.RUN, "plasmarchy-level.wav")
    cmd = ["timeout", "2", "pw-record", "--rate", "16000", "--channels", "1"]
    if source and source != "auto":
        cmd += ["--target", source]
    subprocess.run(cmd + [wav], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return {"db": voice.speech_level(wav)}


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "get"
    if cmd == "get":
        print(json.dumps(get(), ensure_ascii=False))
    elif cmd == "set64" and len(sys.argv) == 4:   # from the widget: value base64-encoded (spaces, special characters)
        import base64
        print(json.dumps(set_value(sys.argv[2], base64.b64decode(sys.argv[3]).decode("utf-8"))))
    elif cmd == "set" and len(sys.argv) >= 4:
        print(json.dumps(set_value(sys.argv[2], " ".join(sys.argv[3:]))))
    elif cmd == "level":
        print(json.dumps(level(sys.argv[2] if len(sys.argv) > 2 else "auto")))
    elif cmd == "sample":
        import base64
        print(json.dumps(voice.speak(base64.b64encode(tr("Hello! This is how I sound as your AI assistant.")
                                                      .encode()).decode(), wait=True)))
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
