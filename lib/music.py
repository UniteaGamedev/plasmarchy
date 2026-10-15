#!/usr/bin/python3 -I
"""Built-in music for the top bar - no browser or desktop app needed.

Spotify (Premium): spotify_player (librespot) runs as a background daemon and appears as the Spotify Connect
device "Plasmarchy". YouTube Music: yt-dlp finds songs, mpv plays them (audio only); a picked song starts as a
radio (YouTube mix) so next/previous work. The widget shows/controls both through MPRIS (mpv needs mpv-mpris).

  music.py status                   JSON: what is installed / signed in / running, per source
  music.py login                    sign in to Spotify once (opens the browser)
  music.py start                    start the Spotify background player (if not running)
  music.py playlists                JSON: liked songs + your Spotify playlists
  music.py search <query>           JSON: Spotify tracks, playlists, albums, artists
  music.py play <kind> <id>         Spotify: track | playlist | album | artist | liked
  music.py yt-search <query>        JSON: songs on YouTube Music
  music.py yt-play <id|url>         play a song (as a radio) or a YouTube/YouTube Music link
"""
import glob
import json
import os
import shutil
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from i18n import tr  # noqa: E402

HOME = os.path.expanduser("~")
RUN = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
MPV_SOCKET = os.path.join(RUN, "plasmarchy-mpv.sock")
MPRIS_PLUGINS = ["/etc/mpv/scripts/mpris.so", "/usr/share/mpv/scripts/mpris.so", "/usr/lib/mpv-mpris/mpris.so",
                 os.path.join(HOME, ".config/mpv/scripts/mpris.so")]
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.join(HOME, ".cache")), "spotify-player")
DEVICE = "Plasmarchy"


def binary():
    return shutil.which("spotify_player")


def authenticated():
    return bool(glob.glob(os.path.join(CACHE, "credentials*.json")) or glob.glob(os.path.join(CACHE, "**", "credentials*"), recursive=True))


def running():
    return subprocess.run(["pgrep", "-x", "spotify_player"], capture_output=True).returncode == 0


def status():
    return {"installed": bool(binary()), "authenticated": authenticated(), "running": running(),
            "youtube": yt_status()}


# --- YouTube Music (yt-dlp + mpv) -------------------------------------------------------------------
def mpris_plugin():
    return next((p for p in MPRIS_PLUGINS if os.path.isfile(p)), "")


def yt_status():
    missing = [p for p, ok in (("yt-dlp", shutil.which("yt-dlp")), ("mpv", shutil.which("mpv")),
                               ("mpv-mpris", mpris_plugin())) if not ok]
    return {"installed": not missing, "missing": missing}


def yt_search(query):
    import urllib.parse

    def run(url):
        out = subprocess.run(["yt-dlp", "--flat-playlist", "--dump-single-json", "--no-warnings", url],
                             capture_output=True, text=True, timeout=40)
        return json.loads(out.stdout).get("entries", []) if out.returncode == 0 and out.stdout else []
    # YouTube Music's song search first, plain YouTube as a fallback
    entries = run("https://music.youtube.com/search?q=" + urllib.parse.quote(query) + "#songs") \
        or run("ytsearch15:" + query)
    items = []
    for e in entries[:20]:
        if not e.get("id"):
            continue
        d = int(e.get("duration") or 0)
        thumbs = e.get("thumbnails") or []
        items.append({"kind": "yt", "id": e["id"], "name": e.get("title", ""),
                      "sub": " · ".join(x for x in (e.get("channel") or e.get("uploader") or "",
                                                    f"{d // 60}:{d % 60:02d}" if d else "") if x),
                      "image": (thumbs[-1].get("url", "") if thumbs else "")})
    return {"items": items}


def mpv_command(*cmd):
    import socket
    s = socket.socket(socket.AF_UNIX)
    s.settimeout(3)
    s.connect(MPV_SOCKET)
    s.sendall((json.dumps({"command": list(cmd)}) + "\n").encode())
    s.close()


def yt_play(target):
    if not yt_status()["installed"]:
        raise SystemExit(tr("YouTube Music isn't set up yet: {0}", "plasmarchy music setup youtube"))
    # a song id starts as a radio (YouTube mix), links are played as they are
    url = target if "://" in target else f"https://music.youtube.com/watch?v={target}&list=RDAMVM{target}"
    try:
        mpv_command("loadfile", url, "replace")
    except OSError:   # no player running yet
        args = ["mpv", "--no-video", "--idle=yes", "--force-window=no", "--no-terminal",
                f"--input-ipc-server={MPV_SOCKET}", "--ytdl-format=bestaudio/best", "--title=YouTube Music"]
        plugin = mpris_plugin()
        if plugin and not plugin.startswith("/etc/mpv/scripts") and "/.config/mpv/scripts" not in plugin:
            args.append(f"--script={plugin}")   # not in an auto-loaded scripts folder
        subprocess.Popen(args + [url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    return {"ok": True}


def start():
    if not binary():
        raise SystemExit(tr("spotify-player is not installed (sudo pacman -S spotify-player)"))
    if not running():
        subprocess.Popen([binary(), "--daemon", "-o", f'device.name="{DEVICE}"', "-o", "device.volume=80"],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        for _ in range(30):   # until the daemon answers
            time.sleep(0.3)
            if sp(["get", "key", "devices"], timeout=5, check=False) is not None:
                break
    return {"ok": True}


def sp(args, timeout=20, check=True):
    """Run a spotify_player CLI command and return its JSON output (None on failure)."""
    out = subprocess.run([binary(), *args], capture_output=True, text=True, timeout=timeout)
    if out.returncode != 0:
        if check:
            raise SystemExit((out.stderr or out.stdout).strip()[-300:] or tr("Spotify command failed"))
        return None
    try:
        return json.loads(out.stdout) if out.stdout.strip() else {}
    except ValueError:
        return {}


def ident(x):
    """IDs come as plain strings, "spotify:type:id" URIs or {"id": ...} objects."""
    if isinstance(x, dict):
        x = x.get("id") or x.get("uri") or ""
    return str(x).rsplit(":", 1)[-1]


def names(lst):
    return ", ".join(a.get("name", "") for a in (lst or []) if isinstance(a, dict))


def image(item):
    imgs = item.get("images") or (item.get("album") or {}).get("images") or []
    if imgs and isinstance(imgs, list):
        best = sorted(imgs, key=lambda i: abs((i.get("width") or 300) - 300))[0]
        return best.get("url", "")
    return ""


def norm(item, kind):
    sub = {"track": lambda i: names(i.get("artists")),
           "album": lambda i: names(i.get("artists")),
           "artist": lambda i: tr("Artist"),
           "playlist": lambda i: (i.get("owner") or {}).get("display_name") or (i.get("owner") or {}).get("name", "")
           if isinstance(i.get("owner"), dict) else ""}[kind](item)
    return {"kind": kind, "id": ident(item.get("id") or item), "name": item.get("name", ""), "sub": sub or "",
            "image": image(item)}


def playlists():
    start()
    data = sp(["get", "key", "user-playlists"]) or []
    items = data if isinstance(data, list) else data.get("items", [])
    return [{"kind": "liked", "id": "", "name": tr("Liked songs"), "sub": "Spotify", "image": ""}] + \
           [norm(p, "playlist") for p in items if isinstance(p, dict)]


def search(query):
    start()
    data = sp(["search", query]) or {}
    out = {}
    for kind, key in (("track", "tracks"), ("artist", "artists"), ("album", "albums"), ("playlist", "playlists")):
        items = data.get(key, [])
        if isinstance(items, dict):
            items = items.get("items", [])
        out[key] = [norm(i, kind) for i in items[:8] if isinstance(i, dict)]
    return out


def play(kind, item_id):
    start()
    if kind == "liked":
        sp(["playback", "start", "liked"])
    elif kind == "track":
        sp(["playback", "start", "track", "--id", item_id])
    elif kind in ("playlist", "album", "artist"):
        sp(["playback", "start", "context", "--id", item_id, kind])
    else:
        raise SystemExit(tr("Unknown item: {0}", kind))
    return {"ok": True}


def login():
    if not binary():
        raise SystemExit(tr("spotify-player is not installed (sudo pacman -S spotify-player)"))
    os.execv(binary(), [binary(), "authenticate"])


def main():
    a = sys.argv[1:]
    cmd = a[0] if a else "status"
    try:
        if cmd == "status":
            result = status()
        elif cmd == "start":
            result = start()
        elif cmd == "login":
            login()
            return
        elif cmd == "playlists":
            result = {"items": playlists()}
        elif cmd == "search" and len(a) >= 2:
            result = search(" ".join(a[1:]))
        elif cmd == "search64" and len(a) == 2:   # from the widget
            import base64
            result = search(base64.b64decode(a[1]).decode("utf-8"))
        elif cmd == "yt-search" and len(a) >= 2:
            result = yt_search(" ".join(a[1:]))
        elif cmd == "yt-search64" and len(a) == 2:   # from the widget
            import base64
            result = yt_search(base64.b64decode(a[1]).decode("utf-8"))
        elif cmd == "yt-play" and len(a) == 2:
            result = yt_play(a[1])
        elif cmd == "play" and len(a) >= 2:
            result = play(a[1], a[2] if len(a) > 2 and a[2] != "-" else "")
        else:
            raise SystemExit(__doc__)
    except subprocess.TimeoutExpired:
        result = {"error": tr("Spotify did not answer in time")}
    except SystemExit as e:
        if cmd in ("status",) or str(e) == __doc__:
            raise
        result = {"error": str(e)}
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
