#!/usr/bin/python3 -I
"""Theme catalog: more themes that can be installed on demand (extra-themes/ in the Plasmarchy repository).

Plasmarchy ships a few core themes; the catalog lives next to them on GitHub (free to host, and anyone can
add a theme with a pull request). Installed catalog themes go to ~/.local/share/plasmarchy/themes-extra/.

  themestore.py list [--refresh]           JSON: catalog with "installed" flags
  themestore.py install <slug> [--from <dir>]   download a theme (or copy it from a local extra-themes/ folder)
  themestore.py remove <slug>
"""
import json
import os
import shutil
import sys
import tempfile
import time
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from i18n import tr  # noqa: E402
from plasmarchy_common import BASE, BUILTIN_THEMES, CACHE, hidden_themes, set_hidden  # noqa: E402

REPO_RAW = os.environ.get("PLASMARCHY_THEMES_URL",
                          "https://raw.githubusercontent.com/UniteaGamedev/plasmarchy/main/extra-themes/")
EXTRA = os.path.join(BASE, "themes-extra")
INDEX_CACHE = os.path.join(CACHE, "theme-catalog.json")
THUMBS = os.path.join(CACHE, "catalog-thumbs")


def fetch(url, timeout=30):
    req = urllib.request.Request(url, headers={"User-Agent": "plasmarchy"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def catalog(refresh=False):
    try:
        if not refresh and time.time() - os.path.getmtime(INDEX_CACHE) < 3600:
            return json.load(open(INDEX_CACHE))
    except (OSError, ValueError):
        pass
    data = json.loads(fetch(REPO_RAW + "index.json"))
    os.makedirs(CACHE, exist_ok=True)
    json.dump(data, open(INDEX_CACHE, "w"))
    return data


def thumb(slug):
    """Local copy of a theme's small preview image (for the catalog view)."""
    out = os.path.join(THUMBS, slug + ".jpg")
    if not os.path.isfile(out):
        os.makedirs(THUMBS, exist_ok=True)
        try:
            open(out, "wb").write(fetch(REPO_RAW + urllib.parse.quote(slug) + "/thumb.jpg"))
        except OSError:
            return ""
    return out


def installed():
    return sorted(s for s in os.listdir(EXTRA) if os.path.isfile(os.path.join(EXTRA, s, "colors.toml"))) \
        if os.path.isdir(EXTRA) else []


def removed_builtins():
    """Built-in themes the user removed - offered again in the catalog (they are still on disk)."""
    out = []
    for slug in sorted(hidden_themes()):
        d = os.path.join(BUILTIN_THEMES, slug)
        if not os.path.isfile(os.path.join(d, "colors.toml")):
            continue
        thumb_path = os.path.join(THUMBS, slug + ".jpg")
        bgs = [os.path.join(d, "backgrounds", f) for f in sorted(os.listdir(os.path.join(d, "backgrounds")))] \
            if os.path.isdir(os.path.join(d, "backgrounds")) else []
        if bgs and not os.path.isfile(thumb_path):
            os.makedirs(THUMBS, exist_ok=True)
            import subprocess
            subprocess.run(["magick", bgs[0], "-resize", "480x300^", "-gravity", "center", "-extent", "480x300",
                            thumb_path], capture_output=True)
        name = slug
        for line in open(os.path.join(d, "kde.conf")) if os.path.isfile(os.path.join(d, "kde.conf")) else []:
            if line.startswith("NAME="):
                name = line.split("=", 1)[1].strip().strip('"')
        out.append({"slug": slug, "name": name if name != slug else " ".join(w.capitalize() for w in slug.split("-")),
                    "animation": "", "size": 0, "installed": False, "builtin": True,
                    "thumbPath": thumb_path if os.path.isfile(thumb_path) else ""})
    return out


def cmd_list(refresh=False):
    try:
        data = catalog(refresh)
    except (OSError, ValueError) as e:
        data = {"error": tr("Theme catalog unavailable ({0})", type(e).__name__), "themes": []}
    have = set(installed())
    for t in data["themes"]:
        t["installed"] = t["slug"] in have
        t["thumbPath"] = thumb(t["slug"])
    data["themes"] = removed_builtins() + data["themes"]
    print(json.dumps(data, ensure_ascii=False))


def cmd_install(slug, local=None):
    if not slug.replace("-", "").isalnum():
        raise SystemExit(tr("Unknown theme: {0}", slug))
    if slug in hidden_themes() and os.path.isdir(os.path.join(BUILTIN_THEMES, slug)):   # a removed built-in theme
        set_hidden(slug, False)
        print(slug)
        return
    os.makedirs(EXTRA, exist_ok=True)
    tmp = tempfile.mkdtemp(dir=EXTRA, prefix=".install-")
    try:
        if local and os.path.isdir(os.path.join(local, slug)):
            shutil.copytree(os.path.join(local, slug), os.path.join(tmp, slug))
        else:
            entry = next((t for t in catalog()["themes"] if t["slug"] == slug), None)
            if not entry:
                raise SystemExit(tr("Unknown theme: {0}", slug))
            for rel in entry["files"]:
                dest = os.path.join(tmp, slug, rel)
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                open(dest, "wb").write(fetch(REPO_RAW + urllib.parse.quote(f"{slug}/{rel}"), timeout=120))
        target = os.path.join(EXTRA, slug)
        if os.path.isdir(target):
            shutil.rmtree(target)
        os.replace(os.path.join(tmp, slug), target)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print(slug)


def cmd_remove(slug):
    target = os.path.join(EXTRA, slug)
    if not os.path.isdir(target):
        raise SystemExit(tr("Theme '{0}' is not installed from the catalog", slug))
    shutil.rmtree(target)
    print(slug)


def main():
    a = sys.argv[1:]
    if a[:1] == ["list"]:
        cmd_list("--refresh" in a)
    elif a[:1] == ["install"] and len(a) >= 2:
        cmd_install(a[1], a[a.index("--from") + 1] if "--from" in a else None)
    elif a[:1] == ["remove"] and len(a) == 2:
        cmd_remove(a[1])
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
