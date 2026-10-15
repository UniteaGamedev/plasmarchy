#!/usr/bin/python3 -I
"""Voice for the AI assistant - fully local, nothing leaves the computer.

  voice.py status               JSON: set up? (speech recognition / text-to-speech)
  voice.py setup                one-time setup: Piper + voice, build whisper.cpp + model
  voice.py record-start         start recording via PipeWire
  voice.py record-stop          stop recording, transcribe -> JSON {"text"}
  voice.py listen               listen until an utterance ends (speech pause) -> JSON {"text"}
  voice.py speak [--wait] <b64> read text aloud (Markdown is stripped); --wait: return after playback
  voice.py stop                 stop speaking/listening
  voice.py mic                  probe all microphones and remember the one with real speech signal (VOICE_SOURCE)

Settings (~/.config/plasmarchy/assistant.conf): VOICE_MODEL=small|base|medium, VOICE_LANG (default: system
language), VOICE_TTS (default: a voice for the system language), VOICE_SOURCE=auto|<PipeWire source>
"""
import base64
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tarfile
import tempfile
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from i18n import language, tr  # noqa: E402

HOME = os.path.expanduser("~")
DATA = os.path.join(os.environ.get("XDG_DATA_HOME", os.path.join(HOME, ".local/share")), "plasmarchy", "voice")
RUN = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
CONF = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.join(HOME, ".config")), "plasmarchy", "assistant.conf")
WHISPER_TAG = "v1.9.5"
PIPER_URL = "https://github.com/rhasspy/piper/releases/download/2023.11.14-2/piper_linux_x86_64.tar.gz"
VOICES = "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0"
MODELS = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main"
REC_WAV = os.path.join(RUN, "plasmarchy-voice.wav")
REC_PID = os.path.join(RUN, "plasmarchy-voice-rec.pid")
SPEAK_PID = os.path.join(RUN, "plasmarchy-voice-speak.pid")
DEFAULT_VOICES = {"en": "en_US-ryan-medium", "de": "de_DE-thorsten-medium", "fr": "fr_FR-siwis-medium",
                  "es": "es_ES-davefx-medium", "it": "it_IT-riccardo-x_low", "nl": "nl_NL-mls-medium",
                  "pl": "pl_PL-darkman-medium", "pt": "pt_BR-faber-medium"}


def conf():
    lang = language()
    c = {"VOICE_MODEL": "small", "VOICE_LANG": lang,
         "VOICE_TTS": DEFAULT_VOICES.get(lang, DEFAULT_VOICES["en"]), "VOICE_SOURCE": "auto"}
    if os.path.isfile(CONF):
        for line in open(CONF):
            if "=" in line and not line.lstrip().startswith("#"):
                k, v = line.strip().split("=", 1)
                c[k.strip()] = v.strip().strip('"')
    return c


def paths():
    c = conf()
    region, name, quality = c["VOICE_TTS"].split("-", 2)      # e.g. de_DE, thorsten, medium
    lang = region.split("_")[0]
    return {
        "whisper": os.path.join(DATA, "whisper.cpp", "build", "bin", "whisper-cli"),
        "model": os.path.join(DATA, "models", f"ggml-{c['VOICE_MODEL']}.bin"),
        "piper": os.path.join(DATA, "piper", "piper"),
        "voice": os.path.join(DATA, "voices", c["VOICE_TTS"] + ".onnx"),
        "voice_url": f"{VOICES}/{lang}/{region}/{name}/{quality}/{c['VOICE_TTS']}.onnx",
    }


def status():
    p = paths()
    return {"stt": os.path.isfile(p["whisper"]) and os.path.isfile(p["model"]),
            "tts": os.path.isfile(p["piper"]) and os.path.isfile(p["voice"]),
            "recording": os.path.exists(REC_PID)}


def download(url, dest):
    if os.path.isfile(dest):
        return
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    print("  " + tr("downloading {0} …", os.path.basename(dest)), flush=True)
    tmp = f"{dest}.{os.getpid()}.part"   # per process: parallel downloads must not share a file
    try:
        with urllib.request.urlopen(url, timeout=60) as r, open(tmp, "wb") as f:
            shutil.copyfileobj(r, f, 1 << 20)
            expected = int(r.headers.get("Content-Length") or 0)
        if expected and os.path.getsize(tmp) != expected:   # connection dropped without an error
            raise OSError(f"incomplete download: {os.path.getsize(tmp)} of {expected} bytes")
        os.replace(tmp, dest)
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)


def setup():
    p = paths()
    os.makedirs(DATA, exist_ok=True)
    # Text-to-speech: Piper (prebuilt) + voice
    if not os.path.isfile(p["piper"]):
        tgz = os.path.join(DATA, "piper.tar.gz")
        download(PIPER_URL, tgz)
        with tarfile.open(tgz) as t:
            t.extractall(DATA, filter="data")
        os.remove(tgz)
    download(p["voice_url"], p["voice"])
    download(p["voice_url"] + ".json", p["voice"] + ".json")
    # Speech recognition: build whisper.cpp ourselves (cmake from a private Python env if needed)
    if not os.path.isfile(p["whisper"]):
        src = os.path.join(DATA, "whisper.cpp")
        if not os.path.isdir(src):
            print("  " + tr("downloading {0} …", "whisper.cpp"), flush=True)
            subprocess.run(["git", "-c", "advice.detachedHead=false", "clone", "-q", "--depth", "1", "--branch", WHISPER_TAG,
                            "https://github.com/ggml-org/whisper.cpp", src], check=True)
        cmake = shutil.which("cmake")
        if not cmake:
            venv = os.path.join(DATA, "buildenv")
            subprocess.run([sys.executable, "-m", "venv", venv], check=True)
            subprocess.run([os.path.join(venv, "bin", "pip"), "install", "-q", "cmake"], check=True)
            cmake = os.path.join(venv, "bin", "cmake")
        print("  " + tr("building whisper.cpp (takes a few minutes) …"), flush=True)
        subprocess.run([cmake, "-S", src, "-B", os.path.join(src, "build"), "-DCMAKE_BUILD_TYPE=Release",
                        "-DBUILD_SHARED_LIBS=OFF", "-DWHISPER_BUILD_TESTS=OFF", "-DWHISPER_BUILD_EXAMPLES=ON"],
                       check=True, stdout=subprocess.DEVNULL)
        subprocess.run([cmake, "--build", os.path.join(src, "build"), "-j", str(os.cpu_count() or 4),
                        "--target", "whisper-cli"], check=True, stdout=subprocess.DEVNULL)
    download(f"{MODELS}/ggml-{conf()['VOICE_MODEL']}.bin", p["model"])
    print(json.dumps(status()))


def set_conf(key, value):
    lines = open(CONF).read().splitlines() if os.path.isfile(CONF) else []
    lines = [l for l in lines if not l.strip().startswith(key + "=")] + [f"{key}={value}"]
    os.makedirs(os.path.dirname(CONF), exist_ok=True)
    open(CONF, "w").write("\n".join(lines) + "\n")


def speech_level(wav):
    """Level in the speech band (300-3400 Hz) in dB - hum/DC offset don't count."""
    out = subprocess.run(["ffmpeg", "-hide_banner", "-i", wav, "-af", "highpass=f=300,lowpass=f=3400,volumedetect",
                          "-f", "null", "-"], capture_output=True, text=True).stderr
    m = re.search(r"mean_volume: (-?[\d.]+) dB", out)
    return float(m.group(1)) if m else -120.0


def detect_mic():
    """Record briefly from every microphone and pick the one with the most signal in the speech band.
    (Laptops often report a dead analog input as default while the built-in microphone is another source.)"""
    sources = [l.split("\t")[1] for l in subprocess.run(["pactl", "list", "sources", "short"], capture_output=True,
               text=True).stdout.splitlines() if "\t" in l and ".monitor" not in l and "input" in l]
    levels = {}
    for src in sources:
        wav = os.path.join(RUN, "plasmarchy-mic-test.wav")
        subprocess.run(["timeout", "1.5", "pw-record", "--target", src, "--rate", "16000", "--channels", "1", wav],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        levels[src] = speech_level(wav)
    if not levels:
        return {"error": tr("No microphone found")}
    best = max(levels, key=levels.get)
    set_conf("VOICE_SOURCE", best)
    return {"source": best, "levels": levels}


def record_start():
    stop_speaking()
    if os.path.exists(REC_PID):
        return {"recording": True}
    target = conf()["VOICE_SOURCE"]
    if target == "auto":
        target = detect_mic().get("source", "auto")
    cmd = ["pw-record", "--rate", "16000", "--channels", "1", "--format", "s16"]
    if target and target != "auto":
        cmd += ["--target", target]
    proc = subprocess.Popen(cmd + [REC_WAV],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    open(REC_PID, "w").write(str(proc.pid))
    return {"recording": True}


LISTEN_PID = os.path.join(RUN, "plasmarchy-voice-listen.pid")


def listen(max_wait=30.0, max_len=25.0, silence=1.1):
    """Conversation mode: wait for speech, record until a speech pause, transcribe.
    The level is measured in the speech band (high-pass); the noise floor is calibrated first."""
    import array
    stop_speaking()
    target = conf()["VOICE_SOURCE"]
    if target == "auto":
        target = detect_mic().get("source", "auto")
    cmd = ["pw-record", "--rate", "16000", "--channels", "1", "--format", "s16"]
    if target and target != "auto":
        cmd += ["--target", target]
    proc = subprocess.Popen(cmd + ["-"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    open(LISTEN_PID, "w").write(str(proc.pid))
    frame = 480                      # 30 ms at 16 kHz
    prev_x = prev_y = 0.0
    floor, calib, frames = None, [], []
    started, quiet, waited = False, 0.0, 0.0
    try:
        while True:
            data = proc.stdout.read(frame * 2)
            if not data or len(data) < frame * 2:
                break
            samples = array.array("h", data)
            energy = 0.0
            for x in samples:        # simple high-pass against hum/DC offset
                y = 0.97 * (prev_y + x - prev_x)
                prev_x, prev_y = x, y
                energy += y * y
            rms = (energy / frame) ** 0.5
            if floor is None:
                calib.append(rms)
                if len(calib) >= 12:  # ~0.36 s noise floor
                    floor = max(sorted(calib)[len(calib) // 2], 30.0)
                continue
            loud = rms > floor * 2.6
            if not started:
                waited += 0.03
                frames = (frames + [data])[-20:]   # keep 0.6 s pre-roll (word onset)
                if loud:
                    started = True
                elif waited > max_wait:
                    return {"timeout": True}
                continue
            frames.append(data)
            quiet = 0.0 if loud else quiet + 0.03
            if quiet >= silence or len(frames) * 0.03 >= max_len:
                break
    finally:
        proc.terminate()
        try:
            os.remove(LISTEN_PID)
        except OSError:
            pass
    if not started:
        return {"timeout": True}
    import wave
    with wave.open(REC_WAV, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(16000)
        w.writeframes(b"".join(frames))
    return transcribe()


def record_stop():
    if not os.path.exists(REC_PID):
        return {"error": tr("No recording active")}
    try:
        os.kill(int(open(REC_PID).read()), signal.SIGINT)
    except (OSError, ValueError):
        pass
    os.remove(REC_PID)
    subprocess.run(["sleep", "0.3"])
    return transcribe()


def transcribe():
    p = paths()
    if not status()["stt"]:
        return {"error": tr("Speech recognition is not set up (plasmarchy voice setup)")}
    # Remove hum/DC offset and normalize loudness - laptop digital mics produce both
    clean = os.path.join(RUN, "plasmarchy-voice-clean.wav")
    if shutil.which("ffmpeg") and subprocess.run(
            ["ffmpeg", "-loglevel", "error", "-y", "-i", REC_WAV, "-af", "highpass=f=90,dynaudnorm",
             "-ar", "16000", "-ac", "1", clean]).returncode == 0:
        source_wav = clean
    else:
        source_wav = REC_WAV
    out = subprocess.run([p["whisper"], "-m", p["model"], "-f", source_wav, "-l", conf()["VOICE_LANG"],
                          "-nt", "-np", "-t", str(min(8, os.cpu_count() or 4))],
                         capture_output=True, text=True)
    text = " ".join(line.strip() for line in out.stdout.splitlines() if line.strip())
    # Never send Whisper's noise placeholders ([MUSIC], *knocking*, (noise) ...) as a message
    text = re.sub(r"\[[^\]]*\]|\*[^*]*\*|\([^)]*\)", "", text).strip(" .,!?-")
    if not text:
        return {"error": tr("Didn't catch that – speak a bit closer to the microphone (check it in the settings)")}
    return {"text": text}


def plain(text):
    """Strip Markdown before speaking."""
    text = re.sub(r"```.*?```", " (" + tr("code example omitted") + ") ", text, flags=re.S)
    text = re.sub(r"`([^`]*)`", r"\1", text)
    text = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"^[#>\-*+]+\s*|\*\*|__|[*_~|]", "", text, flags=re.M)
    return re.sub(r"\s+\n", "\n", text).strip()


def speak(b64, wait=False):
    stop_speaking()
    p = paths()
    if not status()["tts"]:
        return {"error": tr("Text-to-speech is not set up (plasmarchy voice setup)")}
    text = plain(base64.b64decode(b64).decode("utf-8"))
    wav = os.path.join(RUN, "plasmarchy-voice-answer.wav")
    subprocess.run([p["piper"], "--model", p["voice"], "--output_file", wav], input=text, text=True,
                   capture_output=True, cwd=os.path.dirname(p["piper"]))
    proc = subprocess.Popen(["pw-play", wav], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                            start_new_session=True)
    open(SPEAK_PID, "w").write(str(proc.pid))
    if wait:
        proc.wait()
        return {"spoken": True}
    return {"speaking": True}


def stop_speaking():
    for f in (SPEAK_PID, LISTEN_PID):
        try:
            os.kill(int(open(f).read()), signal.SIGTERM)
        except (OSError, ValueError):
            pass
        try:
            os.remove(f)
        except OSError:
            pass
    return {"stopped": True}


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    if cmd == "setup":
        setup()
        return
    result = {"status": status, "record-start": record_start, "record-stop": record_stop,
              "stop": stop_speaking, "mic": detect_mic}.get(cmd)
    if cmd == "speak":
        result = lambda: speak(sys.argv[-1], "--wait" in sys.argv)  # noqa: E731
    if cmd == "listen":
        result = listen
    if not result:
        raise SystemExit(__doc__)
    print(json.dumps(result()))


if __name__ == "__main__":
    main()
