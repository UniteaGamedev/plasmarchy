#!/usr/bin/python3
"""Wake word service (runs in its own Python env voice/wakeenv).

Listens locally with openWakeWord for the configured wake word (WAKE_WORD in assistant.conf) and then starts
a conversation (plasmarchy talk). Detection pauses during a conversation so spoken answers can't trigger it.
Nothing leaves the computer.

  wake.py            run the service (started by the systemd unit plasmarchy-wake)
  wake.py words      available wake words as JSON
"""
import json
import os
import subprocess
import sys
import time

HOME = os.path.expanduser("~")
CONF = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.join(HOME, ".config")), "plasmarchy", "assistant.conf")
RUN = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
TALK_PID = os.path.join(RUN, "plasmarchy-talk.pid")
BIN = os.path.join(HOME, ".local/bin/plasmarchy")
WORDS = {"hey_jarvis": "Hey Jarvis", "alexa": "Alexa", "hey_mycroft": "Hey Mycroft", "hey_marvin": "Hey Marvin"}
CHIME = next((p for p in ("/usr/share/sounds/ocean/stereo/message-new-instant.oga",
                          "/usr/share/sounds/freedesktop/stereo/message-new-instant.oga",
                          "/usr/share/sounds/freedesktop/stereo/message.oga") if os.path.isfile(p)), None)


def conf():
    c = {"WAKE_WORD": "off", "WAKE_SENSITIVITY": "0.5", "VOICE_SOURCE": "auto"}
    if os.path.isfile(CONF):
        for line in open(CONF):
            if "=" in line and not line.lstrip().startswith("#"):
                k, v = line.strip().split("=", 1)
                c[k.strip()] = v.strip().strip('"')
    return c


def talk_running():
    try:
        pid = int(open(TALK_PID).read())
        return b"talk.py" in open(f"/proc/{pid}/cmdline", "rb").read()
    except (OSError, ValueError):
        return False


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "words":
        print(json.dumps(WORDS, ensure_ascii=False))
        return
    import numpy as np
    import openwakeword
    from openwakeword.model import Model

    c = conf()
    word = c["WAKE_WORD"]
    if word not in WORDS:
        print("wake word is off", file=sys.stderr)
        while True:              # idle quietly instead of a restart loop
            time.sleep(3600)
    threshold = min(0.95, max(0.1, float(c["WAKE_SENSITIVITY"] or 0.5)))
    paths = [p for p in openwakeword.get_pretrained_model_paths() if os.path.basename(p).startswith(word + "_v")]
    model = Model(wakeword_model_paths=paths)
    cmd = ["pw-record", "--rate", "16000", "--channels", "1", "--format", "s16"]
    if c["VOICE_SOURCE"] not in ("", "auto"):
        cmd += ["--target", c["VOICE_SOURCE"]]
    rec = subprocess.Popen(cmd + ["-"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    print(f"listening for '{WORDS[word]}' (threshold {threshold})", file=sys.stderr, flush=True)
    cooldown = 0.0
    while True:
        data = rec.stdout.read(2560)            # 80 ms
        if len(data) < 2560:
            break
        if talk_running() or time.time() < cooldown:
            model.reset()
            continue
        score = max(model.predict(np.frombuffer(data, dtype=np.int16)).values())
        if score >= threshold:
            print(f"wake word detected ({score:.2f})", file=sys.stderr, flush=True)
            if CHIME:
                subprocess.Popen(["pw-play", CHIME], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.Popen([BIN, "talk"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             start_new_session=True)
            model.reset()
            cooldown = time.time() + 3


if __name__ == "__main__":
    main()
