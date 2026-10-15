#!/usr/bin/python3 -I
"""AI assistant backend: routes questions to connected AI CLIs - with error handling and a fallback chain.

  assistant.py providers                         available AIs as JSON
  assistant.py history                           shared conversation history as JSON
  assistant.py set <KEY> <value>                 store a setting (PROVIDER, ACTIONS, PROVIDER_ORDER, LOCAL_MODEL)
  assistant.py ask [--new] [--provider P] [--voice] <base64-text>
        -> {"answer", "provider", "notice"?}  or  {"error", "kind", "provider"?}

Fallback chain: if an AI hit its limit, is signed out, overloaded or unreachable, the next one answers
automatically (order: PROVIDER_ORDER). A local model (Ollama) sits at the end - it also phrases notices in
languages without a translation catalog. Plasmarchy keeps the conversation history itself, so the context
survives a switch of AI.

Settings (~/.config/plasmarchy/assistant.conf):
  PROVIDER=auto|claude|cursor|codex|gemini|local   preferred AI
  PROVIDER_ORDER="claude cursor codex gemini local" fallback order
  LOCAL_MODEL=qwen3:4b                              Ollama model
  ACTIONS=off|on                                    allow selected desktop actions (Claude only)
  FAST_VOICE=on|off                                 use Claude's fastest model (Haiku) in conversations
"""
import base64
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from i18n import language as system_language, tr  # noqa: E402

HOME = os.path.expanduser("~")
CONF = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.join(HOME, ".config")), "plasmarchy", "assistant.conf")
WORKDIR = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.join(HOME, ".local/state")), "plasmarchy", "assistant")
HISTORY = os.path.join(WORKDIR, "history.json")
OLLAMA = "http://127.0.0.1:11434"
TIMEOUT = 180
FALLBACK_KINDS = {"limit", "auth", "overloaded", "network", "unavailable"}

PROVIDERS = {
    "claude": {"name": "Claude", "bin": "claude"},
    "cursor": {"name": "Cursor", "bin": "cursor-agent"},
    "codex":  {"name": "Codex", "bin": "codex"},
    "gemini": {"name": "Gemini", "bin": "gemini"},
    "local":  {"name": "Local", "bin": None},
}


# --- Settings, language -----------------------------------------------------------------------
def config():
    conf = {"PROVIDER": "auto", "PROVIDER_ORDER": "claude cursor codex gemini local",
            "LOCAL_MODEL": "qwen3:4b", "ACTIONS": "off"}
    if os.path.isfile(CONF):
        for line in open(CONF):
            if "=" in line and not line.lstrip().startswith("#"):
                k, v = line.strip().split("=", 1)
                conf[k.strip()] = v.strip().strip('"')
    return conf


LANG_NAMES = {"de": "German", "en": "English", "fr": "French", "es": "Spanish", "it": "Italian",
              "nl": "Dutch", "pl": "Polish", "pt": "Portuguese", "tr": "Turkish"}


def system_prompt(voice=False):
    lang = LANG_NAMES.get(system_language(), "the user's language")
    p = (f"You are a helpful AI assistant on the user's Linux desktop (KDE Plasma). Answer briefly and kindly "
         f"in the language of the user's message (system language: {lang}). Use Markdown sparingly.")
    if voice:
        p += (" Your answer will be read aloud: reply in short, naturally spoken sentences without lists, tables, "
              "code blocks or emojis.")
    if config().get("ACTIONS") == "on":
        p += (" You may act on the computer, but ONLY with these commands: `plasmarchy app <name>` (open an app), "
              "`plasmarchy theme <name>` / `plasmarchy themes` (theme), `plasmarchy volume <0-100|mute|unmute>`, "
              "`xdg-open <url>` (website/search). Run them when the user asks and confirm briefly.")
    return p


# --- History (our own, so the context survives switching AIs) ---------------------------------
def load_history():
    try:
        return json.load(open(HISTORY))
    except (OSError, ValueError):
        return []


def save_history(h):
    os.makedirs(WORKDIR, exist_ok=True)
    json.dump(h[-40:], open(HISTORY, "w"))


def context_prompt(history, text):
    """For AIs without their own memory: prepend the last turns."""
    if not history:
        return text
    lines = [("User: " if m["role"] == "user" else "Assistant: ") + m["text"] for m in history[-8:]]
    return "Conversation so far:\n" + "\n".join(lines) + "\n\nNew message from the user:\n" + text


# --- Providers --------------------------------------------------------------------------------
def ollama_ok(model=None):
    try:
        tags = json.load(urllib.request.urlopen(OLLAMA + "/api/tags", timeout=1.5))
        names = {m["name"] for m in tags.get("models", [])}
        return model is None or model in names or f"{model}:latest" in names
    except (OSError, ValueError):
        return False


def available():
    found = []
    order = config()["PROVIDER_ORDER"].split()
    for key in order + [k for k in PROVIDERS if k not in order]:
        p = PROVIDERS.get(key)
        if not p:
            continue
        if key == "local":
            if ollama_ok(config()["LOCAL_MODEL"]):
                found.append({"id": key, "name": f"{tr('Local')} ({config()['LOCAL_MODEL']})", "bin": None})
            continue
        path = shutil.which(p["bin"]) or next((c for c in [os.path.join(HOME, ".local/bin", p["bin"])]
                                               if os.path.isfile(c)), None)
        if not path:
            continue
        if key == "claude" and not os.path.isfile(os.path.join(HOME, ".claude", ".credentials.json")):
            continue
        found.append({"id": key, "name": p["name"], "bin": path})
    return found


def chain(requested):
    avail = available()
    first = requested if requested and requested != "auto" else config()["PROVIDER"]
    ids = [p["id"] for p in avail]
    if first in ids:
        i = ids.index(first)
        avail = avail[i:] + avail[:i]
    return avail


def classify(text, status=None):
    """Sort errors into classes - independent of how each CLI phrases them."""
    t = (text or "").lower()
    if status == 429 or re.search(r"usage.?limit|session limit|quota|rate.?limit|too many requests|credits?", t):
        return "limit"
    if status in (401, 403) or re.search(r"log ?in|logged out|unauthori[sz]ed|authenticat|api key|token expired", t):
        return "auth"
    if status in (500, 502, 503, 529) or re.search(r"overloaded|unavailable|server error", t):
        return "overloaded"
    if re.search(r"network|connection|resolve|timed? ?out|offline|econn", t):
        return "network"
    return "other"


def run_cli(provider, text, new, voice):
    b = provider["bin"]
    pid = provider["id"]
    if pid == "claude":
        # No MCP servers: the assistant doesn't need them and loading them costs about a second per question
        cmd = [b, "-p", "--output-format", "json", "--strict-mcp-config", "--append-system-prompt", system_prompt(voice)]
        if voice and config().get("FAST_VOICE", "on") == "on":
            cmd += ["--model", "haiku"]   # conversations: short answers, latency matters more than depth
        if config().get("ACTIONS") == "on":
            cmd += ["--allowedTools", "Bash(plasmarchy:*)", "Bash(xdg-open:*)"]
        if not new:
            cmd.append("--continue")
        cmd.append(text)
    elif pid == "cursor":
        cmd = [b, "-p", "--output-format", "text", text]
    elif pid == "codex":
        cmd = [b, "exec", "--skip-git-repo-check", text]
    else:
        cmd = [b, "-p", text]
    try:
        out = subprocess.run(cmd, cwd=WORKDIR, capture_output=True, text=True, encoding="utf-8",
                             timeout=TIMEOUT, stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        return {"kind": "timeout", "detail": "timeout"}
    except OSError as e:
        return {"kind": "unavailable", "detail": str(e)}
    raw = (out.stdout or "").strip()
    if pid == "claude":
        try:
            data = json.loads(raw)
        except ValueError:
            data = None
        if data is not None:
            if data.get("is_error") or data.get("api_error"):
                detail = data.get("result") or data.get("api_error") or "error"
                return {"kind": classify(f"{data.get('api_error', '')} {detail}", data.get("api_error_status")),
                        "detail": detail}
            return {"answer": data.get("result", "")}
    if out.returncode != 0 or not raw:
        detail = (out.stderr or raw or "no output").strip()[-300:]
        return {"kind": classify(detail), "detail": detail}
    return {"answer": raw}


def run_local(text, history, voice):
    if not ollama_ok(config()["LOCAL_MODEL"]):
        return {"kind": "unavailable", "detail": "Ollama/model not available"}
    messages = [{"role": "system", "content": system_prompt(voice)}]
    messages += [{"role": m["role"], "content": m["text"]} for m in history[-12:] if m["role"] in ("user", "assistant")]
    messages.append({"role": "user", "content": text})
    body = json.dumps({"model": config()["LOCAL_MODEL"], "messages": messages, "stream": False,
                       "think": False}).encode()
    try:
        req = urllib.request.Request(OLLAMA + "/api/chat", data=body, headers={"Content-Type": "application/json"})
        data = json.load(urllib.request.urlopen(req, timeout=TIMEOUT))
        answer = re.sub(r"<think>.*?</think>", "", data["message"]["content"], flags=re.S).strip()
        return {"answer": answer}
    except (OSError, ValueError, KeyError) as e:
        return {"kind": "network", "detail": str(e)}


# --- Notices in the user's language --------------------------------------------------------------
# English templates; translations come from lib/locale/<lang>.json. Languages without a catalog
# get the notice translated by the local model (if available).
MESSAGES = {
    "limit": "{0} reached its usage limit.", "limit_reset": "{0} reached its usage limit, available again at {1}.",
    "auth": "{0} is not signed in.", "overloaded": "{0} is overloaded right now.",
    "network": "{0} can't be reached (network?).", "timeout": "{0} didn't answer in time.",
    "unavailable": "{0} isn't available.", "other": "{0} reports an error: {1}",
    "none": "No AI connected. Sign in to e.g. Claude Code or set up a local model (plasmarchy llm setup).",
    "fallback": "Answer from {0}.",
}


def reset_time(provider_id):
    """Reset time from the cached Claude limits (if known)."""
    if provider_id != "claude":
        return ""
    try:
        cache = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.join(HOME, ".cache")), "plasmarchy",
                             "claude-limits.json")
        for w in json.load(open(cache)).get("windows", []):
            if w["used"] >= 99:
                return datetime.fromisoformat(w["resets_at"]).astimezone().strftime("%H:%M")
    except (OSError, ValueError, KeyError):
        pass
    return ""


def describe(failures, used=None):
    """Short notice about errors/fallbacks in the user's language."""
    from i18n import catalog
    lang = system_language()
    parts = []
    for f in failures:
        kind = f["kind"] if f["kind"] in MESSAGES else "other"
        rt = reset_time(f["id"]) if kind == "limit" else ""
        if rt:
            parts.append(tr(MESSAGES["limit_reset"], f["name"], rt))
        else:
            parts.append(tr(MESSAGES[kind], f["name"], f.get("detail", "")[:160]))
    if used:
        parts.append(tr(MESSAGES["fallback"], used))
    text = " ".join(parts) if parts else tr(MESSAGES["none"])
    if lang == "en" or catalog() or not ollama_ok(config()["LOCAL_MODEL"]):
        return text
    # No catalog for this language: let the local model translate the notice
    res = run_local(f"Translate this short system notice into {LANG_NAMES.get(lang, lang)}. Reply with the "
                    f"translation only:\n{text}", [], False)
    return res.get("answer") or text


# --- Asking ------------------------------------------------------------------------------------
def ask(text, new=False, requested=None, voice=False):
    os.makedirs(WORKDIR, exist_ok=True)
    history = [] if new else load_history()
    providers = chain(requested)
    if not providers:
        return {"error": describe([]), "kind": "none"}
    failures = []
    for i, p in enumerate(providers):
        if p["id"] == "local":
            res = run_local(text, history, voice)
        else:
            # Claude remembers the conversation itself (--continue) - but only if it led the previous turn
            own = p["id"] == "claude" and not new and history and history[-1].get("provider") == "claude"
            prompt = text if own or p["id"] == "claude" and not history else context_prompt(history, text)
            res = run_cli(p, prompt, new or not own, voice)
        if "answer" in res:
            out = {"answer": res["answer"], "provider": p["name"]}
            if failures:
                out["notice"] = describe(failures, used=p["name"])
            history += [{"role": "user", "text": text},
                        {"role": "assistant", "text": res["answer"], "provider": p["id"],
                         **({"notice": out["notice"]} if "notice" in out else {})}]
            save_history(history)
            return out
        failures.append({"id": p["id"], "name": p["name"], "kind": res["kind"], "detail": res.get("detail", "")})
        if res["kind"] not in FALLBACK_KINDS:
            break   # e.g. a content error: don't blindly ask the next AI
    return {"error": describe(failures), "kind": failures[-1]["kind"], "provider": failures[-1]["name"]}


def main():
    args = sys.argv[1:]
    if not args or args[0] == "providers":
        conf = config()
        print(json.dumps({"preferred": conf["PROVIDER"], "actions": conf["ACTIONS"] == "on",
                          "providers": [{k: p[k] for k in ("id", "name")} for p in available()]},
                         ensure_ascii=False))
        return
    if args[0] == "history":
        print(json.dumps([{"role": m["role"], "text": m["text"], "provider": m.get("provider", ""),
                           "notice": m.get("notice", "")}
                          for m in load_history()[-30:]], ensure_ascii=False))
        return
    if args[0] == "set" and len(args) == 3 and args[1] in ("PROVIDER", "ACTIONS", "PROVIDER_ORDER", "LOCAL_MODEL"):
        lines = open(CONF).read().splitlines() if os.path.isfile(CONF) else []
        lines = [l for l in lines if not l.strip().startswith(args[1] + "=")] + [f"{args[1]}={args[2]}"]
        os.makedirs(os.path.dirname(CONF), exist_ok=True)
        open(CONF, "w").write("\n".join(lines) + "\n")
        print(json.dumps({"ok": True}))
        return
    if args[0] == "ask":
        new = "--new" in args
        requested = args[args.index("--provider") + 1] if "--provider" in args else None
        text = base64.b64decode(args[-1]).decode("utf-8").strip()
        if not text:
            print(json.dumps({"error": tr("Empty message"), "kind": "other"}))
            return
        print(json.dumps(ask(text, new, requested, "--voice" in args), ensure_ascii=False))
        return
    raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
