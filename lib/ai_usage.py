#!/usr/bin/python3 -I
"""AI usage for the AI assistant widget.

Claude Code: reads the local logs (~/.claude/projects/**/*.jsonl) - tokens in the current 5-hour window
             (Claude's usage limits are based on it), today, 7 days, per model.
Cursor:      asks cursor.com for usage with the local Cursor login (only when signed in; cached for 5 minutes).
             Unofficial endpoint - may change.
Limits:      plan utilization (5-hour and weekly limit in %) from Anthropic - the same request Claude Code uses
             for /usage, with the local Claude login (cached for 2 minutes).
Alerts:      --notify sends a desktop notification when only NOTIFY_LEFT percent are left
             (~/.config/plasmarchy/assistant.conf, default NOTIFY_LEFT="20 5"), once per limit window.

Usage: ai_usage.py [--json] [--notify]
"""
import base64
import glob
import json
import os
import sqlite3
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from i18n import tr  # noqa: E402

HOME = os.path.expanduser("~")
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.join(HOME, ".cache")), "plasmarchy")
CLAUDE_DIRS = [os.path.join(HOME, ".claude", "projects"),
               os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.join(HOME, ".config")), "claude", "projects")]
CURSOR_DB = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.join(HOME, ".config")),
                         "Cursor", "User", "globalStorage", "state.vscdb")
BLOCK = timedelta(hours=5)
STATE = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.join(HOME, ".local/state")), "plasmarchy")
CONF = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.join(HOME, ".config")), "plasmarchy", "assistant.conf")
LIMIT_NAMES = {"five_hour": "5-hour limit", "seven_day": "Weekly limit"}


# --- Claude Code -------------------------------------------------------------------------------
def claude_entries(since):
    seen, entries = set(), []
    for root in CLAUDE_DIRS:
        for path in glob.glob(os.path.join(root, "**", "*.jsonl"), recursive=True):
            try:
                if datetime.fromtimestamp(os.path.getmtime(path), timezone.utc) < since:
                    continue
                with open(path, encoding="utf-8", errors="replace") as f:
                    for line in f:
                        if '"usage"' not in line:
                            continue
                        try:
                            d = json.loads(line)
                        except ValueError:
                            continue
                        m = d.get("message")
                        if d.get("type") != "assistant" or not isinstance(m, dict) or not m.get("usage"):
                            continue
                        if m.get("model") == "<synthetic>":   # internal placeholders without a real request
                            continue
                        key = (m.get("id"), d.get("requestId"))
                        if key in seen:
                            continue
                        seen.add(key)
                        ts = datetime.fromisoformat(d["timestamp"].replace("Z", "+00:00"))
                        if ts < since:
                            continue
                        u = m["usage"]
                        entries.append({
                            "ts": ts,
                            "model": m.get("model", "?"),
                            "input": u.get("input_tokens", 0) or 0,
                            "output": u.get("output_tokens", 0) or 0,
                            "cache_write": u.get("cache_creation_input_tokens", 0) or 0,
                            "cache_read": u.get("cache_read_input_tokens", 0) or 0,
                        })
            except OSError:
                continue
    return sorted(entries, key=lambda e: e["ts"])


def summarize(entries):
    s = {"messages": len(entries), "input": 0, "output": 0, "cache_write": 0, "cache_read": 0}
    for e in entries:
        for k in ("input", "output", "cache_write", "cache_read"):
            s[k] += e[k]
    s["tokens"] = s["input"] + s["output"] + s["cache_write"]   # excluding cache reads (very cheap)
    return s


def current_block(entries, now):
    """5-hour window like Claude's: starts at the full hour of the first message."""
    start, block = None, []
    for e in entries:
        if start is None or e["ts"] >= start + BLOCK:
            start = e["ts"].replace(minute=0, second=0, microsecond=0)
            block = []
        block.append(e)
    if start is None or now >= start + BLOCK:
        return None
    s = summarize(block)
    s.update({"start": start.isoformat(), "end": (start + BLOCK).isoformat(),
              "remaining_min": int((start + BLOCK - now).total_seconds() // 60)})
    return s


def claude_usage():
    if not any(os.path.isdir(d) for d in CLAUDE_DIRS):
        return {"available": False, "reason": tr("Claude Code not found")}
    now = datetime.now(timezone.utc)
    week = claude_entries(now - timedelta(days=7))
    local_midnight = datetime.now().astimezone().replace(hour=0, minute=0, second=0, microsecond=0)
    today = [e for e in week if e["ts"] >= local_midnight]
    models = {}
    for e in today:
        models.setdefault(e["model"], []).append(e)
    return {
        "available": True,
        "block": current_block(week, now),
        "today": summarize(today),
        "week": summarize(week),
        "models": sorted(({"model": k, **summarize(v)} for k, v in models.items()),
                         key=lambda m: -m["tokens"]),
    }


def claude_limits():
    """Plan utilization in percent (like /usage in Claude Code)."""
    cache_file = os.path.join(CACHE, "claude-limits.json")
    try:
        if time.time() - os.path.getmtime(cache_file) < 120:
            cached = json.load(open(cache_file))
            now = datetime.now(timezone.utc)
            # Refresh right after a reset - otherwise the old, full limit would still be shown
            if not any(w.get("resets_at") and datetime.fromisoformat(w["resets_at"]) <= now
                       for w in cached.get("windows", [])):
                return cached
    except (OSError, ValueError):
        pass
    try:
        cred = json.load(open(os.path.join(HOME, ".claude", ".credentials.json")))["claudeAiOauth"]
    except (OSError, ValueError, KeyError):
        return {"available": False, "reason": tr("Not signed in to Claude")}
    result = {"available": True, "plan": cred.get("subscriptionType", ""), "windows": []}
    try:
        req = urllib.request.Request("https://api.anthropic.com/api/oauth/usage", headers={
            "Authorization": "Bearer " + cred["accessToken"], "anthropic-beta": "oauth-2025-04-20",
            "User-Agent": "plasmarchy"})
        data = json.load(urllib.request.urlopen(req, timeout=6))
        for key, label in LIMIT_NAMES.items():
            w = data.get(key)
            if isinstance(w, dict) and w.get("utilization") is not None:
                # English name; translated on output so the cache stays language-neutral
                result["windows"].append({"id": key, "name": label, "used": round(w["utilization"]),
                                          "resets_at": w.get("resets_at", "")})
    except Exception as e:   # e.g. expired login - Claude Code renews it on its next start
        result = {"available": False, "reason": tr("Limits unavailable ({0})", type(e).__name__)}
    os.makedirs(CACHE, exist_ok=True)
    json.dump(result, open(cache_file, "w"))
    return result


def notify_thresholds():
    left = "20 5"
    if os.path.isfile(CONF):
        for line in open(CONF):
            if line.strip().startswith("NOTIFY_LEFT="):
                left = line.split("=", 1)[1].strip().strip('"')
    return sorted({int(x) for x in left.split() if x.isdigit()}, reverse=True)


def send_notifications(limits):
    """Only one notification per limit window (identified by its reset time) and threshold."""
    if not limits.get("available"):
        return
    path = os.path.join(STATE, "usage-notified.json")
    try:
        sent = json.load(open(path))
    except (OSError, ValueError):
        sent = {}
    changed = False
    for w in limits["windows"]:
        left = 100 - w["used"]
        for t in notify_thresholds():
            key = f"{w['id']}|{w['resets_at'][:16]}|{t}"
            if left <= t and key not in sent:
                reset = ""
                try:
                    reset = " " + tr("Resets at {0}.", datetime.fromisoformat(w["resets_at"]).astimezone().strftime(
                        "%H:%M" if w["id"] == "five_hour" else "%a %H:%M"))
                except ValueError:
                    pass
                subprocess.run(["notify-send", "-a", "Plasmarchy", "-i", "dialog-warning",
                                tr("Claude: only {0}% left", left), tr("{0} {1}% used.", w["name"], w["used"]) + reset],
                               check=False)
                sent[key] = int(time.time())
                changed = True
                break   # per window, only report the strictest threshold reached
    if changed:
        os.makedirs(STATE, exist_ok=True)
        cutoff = time.time() - 14 * 86400
        json.dump({k: v for k, v in sent.items() if v > cutoff}, open(path, "w"))


# --- Cursor ------------------------------------------------------------------------------------
def cursor_usage():
    if not os.path.isfile(CURSOR_DB):
        return {"available": False, "reason": tr("Cursor not found")}
    cache_file = os.path.join(CACHE, "cursor-usage.json")
    try:
        if time.time() - os.path.getmtime(cache_file) < 300:
            return json.load(open(cache_file))
    except (OSError, ValueError):
        pass
    try:
        db = sqlite3.connect(f"file:{CURSOR_DB}?mode=ro", uri=True, timeout=2)
        rows = dict(db.execute("SELECT key, value FROM ItemTable WHERE key LIKE 'cursorAuth/%'").fetchall())
        db.close()
    except sqlite3.Error as e:
        return {"available": False, "reason": tr("Cursor data not readable ({0})", e)}
    token = rows.get("cursorAuth/accessToken")
    if not token:
        return {"available": False, "reason": tr("Not signed in to Cursor")}
    result = {"available": True, "email": rows.get("cursorAuth/cachedEmail", ""),
              "plan": rows.get("cursorAuth/stripeMembershipType", "")}
    try:
        payload = token.split(".")[1]
        sub = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))["sub"]
        user = sub.split("|")[-1]
        req = urllib.request.Request(
            "https://cursor.com/api/usage?user=" + urllib.parse.quote(user),
            headers={"Cookie": f"WorkosCursorSessionToken={urllib.parse.quote(user)}%3A%3A{token}",
                     "User-Agent": "plasmarchy"})
        data = json.load(urllib.request.urlopen(req, timeout=6))
        models = []
        for name, v in data.items():
            if isinstance(v, dict) and "numRequests" in v:
                models.append({"model": name, "requests": v.get("numRequests", 0),
                               "limit": v.get("maxRequestUsage")})
        result.update({"models": models, "since": data.get("startOfMonth", "")})
    except Exception as e:   # network/endpoint: just a hint, the widget stays usable
        result.update({"models": [], "reason": tr("Usage unavailable ({0})", type(e).__name__)})
    os.makedirs(CACHE, exist_ok=True)
    json.dump(result, open(cache_file, "w"))
    return result


# --- Output ------------------------------------------------------------------------------------
def human(n):
    for unit, size in (("M", 1_000_000), ("k", 1_000)):
        if n >= size:
            return f"{n / size:.1f}{unit}"
    return str(n)


def main():
    data = {"claude": claude_usage(), "limits": claude_limits(), "cursor": cursor_usage(),
            "updated": datetime.now().strftime("%H:%M")}
    for w in data["limits"].get("windows", []):   # cache keeps English names; translate for display
        w["name"] = tr(w["name"])
    if "--notify" in sys.argv:
        send_notifications(data["limits"])
    if "--json" in sys.argv:
        print(json.dumps(data))
        return
    lim = data["limits"]
    print(tr("Claude limits") + (f" ({lim.get('plan')})" if lim.get("plan") else ""))
    for w in lim.get("windows", []):
        print("  " + tr("{0} {1}% used.", w["name"], w["used"]))
    if not lim.get("available"):
        print("  " + lim["reason"])
    c = data["claude"]
    print("Claude Code")
    if not c["available"]:
        print("  " + c["reason"])
    else:
        b = c["block"]
        if b:
            print("  " + tr("5h window: {0} tokens, {1} messages, {2}h {3:02d}min left", human(b["tokens"]),
                                b["messages"], b["remaining_min"] // 60, b["remaining_min"] % 60))
        else:
            print("  " + tr("5h window: none active"))
        print("  " + tr("Today:  {0} tokens, {1} messages", human(c["today"]["tokens"]), c["today"]["messages"]))
        print("  " + tr("7 days: {0} tokens, {1} messages", human(c["week"]["tokens"]), c["week"]["messages"]))
        for m in c["models"]:
            print(f"    {m['model']}: {human(m['tokens'])}")
    u = data["cursor"]
    print("Cursor")
    if not u["available"]:
        print("  " + u["reason"])
    else:
        for m in u.get("models", []):
            print(f"  {m['model']}: {m['requests']}" + (f" / {m['limit']}" if m["limit"] else "") + " " + tr("requests"))
        if u.get("reason"):
            print("  " + u["reason"])


if __name__ == "__main__":
    main()
