#!/usr/bin/python3 -I
"""Built-in music for the top bar - no browser or desktop app needed.

Spotify (Premium): spotify_player (librespot) runs as a background daemon and appears as the Spotify Connect
device "Plasmarchy". YouTube Music: yt-dlp finds songs, mpv plays them (audio only); a picked song starts as a
radio (YouTube mix) so next/previous work. The widget shows/controls both through MPRIS (mpv needs mpv-mpris).

  music.py status                   JSON: what is installed / signed in / running, per source
  music.py login                    sign in to Spotify once (opens the browser)
  music.py client-id <id>           use your own Spotify app (own request limit), then sign in again
  music.py start                    start the Spotify background player (if not running)
  music.py playlists                JSON: liked songs + your Spotify playlists
  music.py search <query>           JSON: Spotify tracks, playlists, albums, artists
  music.py play <kind> <id>         Spotify: track | playlist | album | artist | liked
  music.py yt-search <query>        JSON: songs on YouTube Music
  music.py yt-play <id|url>         play a song (as a radio) or a YouTube/YouTube Music link
  music.py yt-now                   JSON: cover of the song our mpv plays
"""
import glob
import json
import os
import re
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


CONFIG = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.join(HOME, ".config")), "spotify-player", "app.toml")


def authenticated():
    """Both parts of the sign in: librespot's credentials (playback) and the Web API token (search, library)."""
    return os.path.isfile(os.path.join(CACHE, "credentials.json")) and bool(glob.glob(os.path.join(CACHE, "*token*.json")))


def rate_limited():
    """True if Spotify answered "429 Too Many Requests" in the player's latest log during the last minute."""
    logs = sorted(glob.glob(os.path.join(CACHE, "spotify-player-*.log")), key=os.path.getmtime)
    if not logs or time.time() - os.path.getmtime(logs[-1]) > 60:
        return False
    with open(logs[-1], errors="replace") as f:
        f.seek(max(0, os.path.getsize(logs[-1]) - 20000))
        return "rate limit" in f.read()


def running():
    return subprocess.run(["pgrep", "-x", "spotify_player"], capture_output=True).returncode == 0


def status():
    yt = yt_status()
    yt["running"] = subprocess.run(["pgrep", "-f", MPV_SOCKET], capture_output=True).returncode == 0   # our mpv
    return {"installed": bool(binary()), "authenticated": authenticated(), "running": running(), "youtube": yt}


# --- YouTube Music (yt-dlp + mpv) -------------------------------------------------------------------
def mpris_plugin():
    return next((p for p in MPRIS_PLUGINS if os.path.isfile(p)), "")


def yt_status():
    missing = [p for p, ok in (("yt-dlp", shutil.which("yt-dlp")), ("mpv", shutil.which("mpv")),
                               ("mpv-mpris", mpris_plugin())) if not ok]
    return {"installed": not missing, "missing": missing}


def ytm_api_search(query):
    """Songs from YouTube Music's own search API (what music.youtube.com uses; about 0.5 s instead of 10+ s
    with yt-dlp). Returns [] if the answer has an unexpected shape, then yt-dlp takes over."""
    import urllib.request
    body = json.dumps({"context": {"client": {"clientName": "WEB_REMIX", "clientVersion": "1.20241111.01.00",
                                              "hl": "en"}},
                       "query": query, "params": "EgWKAQIIAWoMEA4QChADEAQQCRAF"}).encode()   # filter: songs
    req = urllib.request.Request("https://music.youtube.com/youtubei/v1/search?prettyPrint=false", data=body,
                                 headers={"Content-Type": "application/json", "User-Agent": "Mozilla/5.0",
                                          "Origin": "https://music.youtube.com"})
    with urllib.request.urlopen(req, timeout=10) as r:
        data = json.load(r)

    def walk(o):
        if isinstance(o, dict):
            if "musicResponsiveListItemRenderer" in o:
                yield o["musicResponsiveListItemRenderer"]
            else:
                for v in o.values():
                    yield from walk(v)
        elif isinstance(o, list):
            for v in o:
                yield from walk(v)

    def runs(col):
        return [r.get("text", "") for r in col.get("musicResponsiveListItemFlexColumnRenderer", {})
                .get("text", {}).get("runs", [])]

    items = []
    for it in walk(data):
        vid = (it.get("playlistItemData") or {}).get("videoId")
        cols = it.get("flexColumns") or []
        if not vid or not cols:
            continue
        title = "".join(runs(cols[0]))
        info = [x.strip() for x in "".join(runs(cols[1]) if len(cols) > 1 else []).split("•") if x.strip()]
        thumbs = (((it.get("thumbnail") or {}).get("musicThumbnailRenderer") or {}).get("thumbnail") or {}).get("thumbnails") or []
        # info: artist, album, duration (the album is left out to keep the line short)
        sub = " · ".join(x for x in (info[0] if info else "", info[-1] if len(info) > 1 else "") if x)
        items.append({"kind": "yt", "id": vid, "name": title, "sub": sub,
                      "image": thumbs[0]["url"] if thumbs else ""})
        if len(items) >= 20:
            break
    return items


def yt_search(query):
    import urllib.parse
    try:
        items = ytm_api_search(query)
        if items:
            return {"items": items}
    except (OSError, ValueError, KeyError, IndexError, TypeError):
        pass

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
    """Send a command to our mpv and return its "data" (None if there is none)."""
    import socket
    s = socket.socket(socket.AF_UNIX)
    s.settimeout(3)
    s.connect(MPV_SOCKET)
    s.sendall((json.dumps({"command": list(cmd), "request_id": 1}) + "\n").encode())
    buf = b""
    try:
        while True:
            chunk = s.recv(65536)
            if not chunk:
                break
            buf += chunk
            for line in buf.split(b"\n"):
                try:
                    msg = json.loads(line)
                except ValueError:
                    continue
                if msg.get("request_id") == 1:
                    return msg.get("data")
    except OSError:
        return None
    finally:
        s.close()


def yt_now():
    """Cover of the song our mpv plays (mpv doesn't report one for YouTube streams): from the video id."""
    import urllib.parse
    try:
        path = mpv_command("get_property", "path") or ""
    except OSError:
        return {"image": ""}
    vid = (urllib.parse.parse_qs(urllib.parse.urlparse(path).query).get("v") or [""])[0]
    return {"id": vid, "image": f"https://i.ytimg.com/vi/{vid}/mqdefault.jpg" if vid else ""}


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
        spawn(args + [url], "mpv")
    return {"ok": True}


def start():
    if not binary():
        raise SystemExit(tr("spotify-player is not installed (sudo pacman -S spotify-player)"))
    if not running():
        spawn([binary(), "--daemon", "-o", f'device.name="{DEVICE}"', "-o", "device.volume=80"], "spotify", forking=True)
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


def spawn(args, name, forking=False):
    """Start a player in its own systemd unit: started from the widget it would otherwise belong to plasmashell's
    service, and every Plasma restart would stop the music."""
    if shutil.which("systemd-run"):
        unit = f"plasmarchy-{name}-{int(time.time())}"
        extra = ["--property=Type=forking"] if forking else []   # spotify_player --daemon forks itself
        if subprocess.run(["systemd-run", "--user", "--quiet", "--collect", f"--unit={unit}", *extra, *args],
                          capture_output=True).returncode == 0:
            return
    subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL,
                     start_new_session=True)


def stop():
    subprocess.run(["pkill", "-x", "spotify_player"], capture_output=True)
    for _ in range(20):
        if not running():
            break
        time.sleep(0.2)


def login():
    """Sign in (runs in a terminal). spotify_player's "authenticate" saves only the Web API token; the playback
    credentials are saved when the player itself connects, so start it afterwards and wait for them."""
    if not binary():
        raise SystemExit(tr("spotify-player is not installed (sudo pacman -S spotify-player)"))
    stop()
    if subprocess.run([binary(), "authenticate"]).returncode != 0:
        raise SystemExit(tr("Spotify command failed"))
    spawn([binary(), "--daemon", "-o", f'device.name="{DEVICE}"', "-o", "device.volume=80"], "spotify", forking=True)
    for _ in range(120):
        if authenticated():
            print(tr("Spotify is connected. You can close this window."))
            return
        time.sleep(1)
    raise SystemExit(tr("Spotify did not answer in time"))


def set_client_id(client_id):
    """Use your own Spotify app instead of the shared one (its own request limit, and its name on the consent page)."""
    client_id = client_id.strip()
    if not re.fullmatch(r"[0-9a-f]{32}", client_id):
        raise SystemExit(tr("That doesn't look like a Client ID (32 characters, 0-9 and a-f)."))
    text = open(CONFIG).read() if os.path.isfile(CONFIG) else ""
    line = f'client_id = "{client_id}"'
    text = re.sub(r'(?m)^client_id\s*=.*$', line, text) if re.search(r"(?m)^client_id\s*=", text) else line + "\n" + text
    os.makedirs(os.path.dirname(CONFIG), exist_ok=True)
    open(CONFIG, "w").write(text)
    for f in glob.glob(os.path.join(CACHE, "*token*.json")):   # the old app's token
        os.remove(f)
    login()


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
        elif cmd == "client-id" and len(a) == 2:
            set_client_id(a[1])
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
        elif cmd == "yt-now":
            result = yt_now()
        elif cmd == "yt-play" and len(a) == 2:
            result = yt_play(a[1])
        elif cmd == "play" and len(a) >= 2:
            result = play(a[1], a[2] if len(a) > 2 and a[2] != "-" else "")
        else:
            raise SystemExit(__doc__)
    except subprocess.TimeoutExpired:
        result = {"error": tr("Spotify is limiting requests from the shared app right now. With your own free Spotify app this goes away: plasmarchy music client-id") if rate_limited()
                  else tr("Spotify did not answer in time")}
    except SystemExit as e:
        if cmd in ("status",) or str(e) == __doc__:
            raise
        result = {"error": str(e)}
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
