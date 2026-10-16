#!/usr/bin/python3 -I
"""Music for the top bar.

Spotify: the official Spotify app (spotify-launcher). The widget controls it through MPRIS and sends searches
to it; signing in happens once in the app itself. YouTube Music: built in, no app needed. Its search API finds
songs, mpv plays them (audio only) and a picked song starts a radio that never runs out (radio.lua). The widget
shows and controls both through MPRIS (mpv needs mpv-mpris).

  music.py status                   JSON: what is installed / running, per source
  music.py sp-open                  start the Spotify app (or bring it up)
  music.py sp-search <query>        show the search results in the Spotify app
  music.py sp-search64 <base64>     the same, query base64 encoded (from the widget)
  music.py yt-search <query>        JSON: songs on YouTube Music
  music.py yt-play <id|url>         play a song (as a radio) or a YouTube/YouTube Music link
  music.py yt-now                   JSON: cover of the song our mpv plays
  music.py yt-extend <id>           append songs similar to <id> to the queue (used by radio.lua)
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
SPOTIFY_BUS = "org.mpris.MediaPlayer2.spotify"


def spotify_binary():
    for name in ("spotify-launcher", "spotify"):
        path = shutil.which(name)
        if path:
            return [path]
    if shutil.which("flatpak") and subprocess.run(["flatpak", "info", "com.spotify.Client"],
                                                  capture_output=True).returncode == 0:
        return ["flatpak", "run", "com.spotify.Client"]
    return None


def spotify_running():
    return subprocess.run(["busctl", "--user", "status", SPOTIFY_BUS], capture_output=True).returncode == 0


def status():
    yt = yt_status()
    yt["running"] = subprocess.run(["pgrep", "-f", MPV_SOCKET], capture_output=True).returncode == 0   # our mpv
    return {"installed": bool(spotify_binary()), "running": spotify_running(), "youtube": yt}


def sp_open():
    """Start the Spotify app if it isn't running and wait until it can be controlled."""
    cmd = spotify_binary()
    if not cmd:
        raise SystemExit(tr("Spotify isn't set up yet"))
    if not spotify_running():
        spawn(cmd, "spotify")
        for _ in range(60):
            time.sleep(0.5)
            if spotify_running():
                time.sleep(1)   # the app needs a moment before it accepts commands
                break
    return {"ok": True}


def sp_search(query):
    """Show the search results in the Spotify app (Spotify offers no search without a developer app)."""
    import urllib.parse
    sp_open()
    uri = "spotify:search:" + urllib.parse.quote(query)
    subprocess.run(["busctl", "--user", "call", SPOTIFY_BUS, "/org/mpris/MediaPlayer2",
                    "org.mpris.MediaPlayer2.Player", "OpenUri", "s", uri], capture_output=True)
    subprocess.run(["busctl", "--user", "call", SPOTIFY_BUS, "/org/mpris/MediaPlayer2",
                    "org.mpris.MediaPlayer2", "Raise"], capture_output=True)
    return {"ok": True}


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


def ytm_radio(video_id):
    """The song plus YouTube Music's radio queue ("Up next", about 25 similar songs) as [(id, title)]."""
    import urllib.request
    body = json.dumps({"context": {"client": {"clientName": "WEB_REMIX", "clientVersion": "1.20241111.01.00",
                                              "hl": "en"}},
                       "videoId": video_id, "playlistId": "RDAMVM" + video_id, "isAudioOnly": True}).encode()
    req = urllib.request.Request("https://music.youtube.com/youtubei/v1/next?prettyPrint=false", data=body,
                                 headers={"Content-Type": "application/json", "User-Agent": "Mozilla/5.0",
                                          "Origin": "https://music.youtube.com"})
    with urllib.request.urlopen(req, timeout=10) as r:
        data = json.load(r)

    def walk(o):
        if isinstance(o, dict):
            if "playlistPanelVideoRenderer" in o:
                yield o["playlistPanelVideoRenderer"]
            else:
                for v in o.values():
                    yield from walk(v)
        elif isinstance(o, list):
            for v in o:
                yield from walk(v)
    out, seen = [], set()
    for it in walk(data):
        vid = it.get("videoId")
        if vid and vid not in seen:
            seen.add(vid)
            out.append((vid, "".join(r.get("text", "") for r in (it.get("title") or {}).get("runs", []))))
    return out


RADIO_SCRIPT = os.path.join(os.path.dirname(os.path.realpath(__file__)), "radio.lua")


def yt_extend(video_id):
    """Called by radio.lua when the queue runs low: append songs similar to video_id that aren't queued yet."""
    queued = {e.get("filename", "") for e in (mpv_command("get_property", "playlist") or [])}
    added = 0
    for vid, title in ytm_radio(video_id):
        url = "https://music.youtube.com/watch?v=" + vid
        if url in queued:
            continue
        opts = f"force-media-title=%{len(title.encode())}%{title}" if title else ""
        mpv_command("loadfile", url, "append", -1, opts)
        added += 1
    return {"added": added}


def yt_play(target):
    """Play a song as a radio (it and similar songs after it) or a YouTube / YouTube Music link as it is."""
    if not yt_status()["installed"]:
        raise SystemExit(tr("YouTube Music isn't set up yet: {0}", "plasmarchy music setup youtube"))
    if "://" in target:
        queue = [(target, "")]
    else:
        try:
            queue = [("https://music.youtube.com/watch?v=" + vid, title) for vid, title in ytm_radio(target)]
        except (OSError, ValueError):
            queue = []
        if not queue or target not in queue[0][0]:
            queue.insert(0, ("https://music.youtube.com/watch?v=" + target, ""))
    try:
        mpv_command("get_property", "pid")
    except OSError:   # no player running yet: start an empty one, then fill it
        args = ["mpv", "--no-video", "--idle=yes", "--force-window=no", "--no-terminal",
                f"--input-ipc-server={MPV_SOCKET}", "--ytdl-format=bestaudio/best", "--title=YouTube Music",
                f"--script={RADIO_SCRIPT}"]   # keeps the radio going
        plugin = mpris_plugin()
        if plugin and not plugin.startswith("/etc/mpv/scripts") and "/.config/mpv/scripts" not in plugin:
            args.append(f"--script={plugin}")   # not in an auto-loaded scripts folder
        spawn(args, "mpv")
        for _ in range(50):
            time.sleep(0.1)
            try:
                mpv_command("get_property", "pid")
                break
            except OSError:
                continue
    # the title as display name right away: otherwise the link shows until the stream is open
    for n, (url, title) in enumerate(queue):
        opts = f"force-media-title=%{len(title.encode())}%{title}" if title else ""   # %n% quoting: commas are fine
        mpv_command("loadfile", url, "replace" if n == 0 else "append", -1, opts)
    mpv_command("set_property", "pause", False)
    mpv_command("set_property", "mute", False)   # starting a song always means: with sound
    return {"ok": True}


def spawn(args, name):
    """Start a player in its own systemd unit: started from the widget it would otherwise belong to plasmashell's
    service, and every Plasma restart would stop the music."""
    if shutil.which("systemd-run"):
        unit = f"plasmarchy-{name}-{int(time.time())}"
        if subprocess.run(["systemd-run", "--user", "--quiet", "--collect", f"--unit={unit}", *args],
                          capture_output=True).returncode == 0:
            return
    subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL,
                     start_new_session=True)


def main():
    a = sys.argv[1:]
    cmd = a[0] if a else "status"
    try:
        if cmd == "status":
            result = status()
        elif cmd == "sp-open":
            result = sp_open()
        elif cmd == "sp-search" and len(a) >= 2:
            result = sp_search(" ".join(a[1:]))
        elif cmd == "sp-search64" and len(a) == 2:   # from the widget
            import base64
            result = sp_search(base64.b64decode(a[1]).decode("utf-8"))
        elif cmd == "yt-search" and len(a) >= 2:
            result = yt_search(" ".join(a[1:]))
        elif cmd == "yt-search64" and len(a) == 2:   # from the widget
            import base64
            result = yt_search(base64.b64decode(a[1]).decode("utf-8"))
        elif cmd == "yt-extend" and len(a) == 2:
            result = yt_extend(a[1])
        elif cmd == "yt-now":
            result = yt_now()
        elif cmd == "yt-play" and len(a) == 2:
            result = yt_play(a[1])
        else:
            raise SystemExit(__doc__)
    except subprocess.TimeoutExpired:
        result = {"error": tr("YouTube Music did not answer in time")}
    except SystemExit as e:
        if cmd in ("status",) or str(e) == __doc__:
            raise
        result = {"error": str(e)}
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
