#!/usr/bin/python3 -I
"""Regenerate extra-themes/index.json (the theme catalog) and the small preview images.
Run after adding or changing a theme in extra-themes/:   python3 tools/build_theme_index.py"""
import json
import os
import subprocess
import tomllib

ROOT = os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "extra-themes")


def conf(path):
    c = {}
    if os.path.isfile(path):
        for line in open(path):
            if "=" in line and not line.lstrip().startswith("#"):
                k, v = line.strip().split("=", 1)
                c[k.strip()] = v.strip().strip('"')
    return c


themes = []
for slug in sorted(os.listdir(ROOT)):
    d = os.path.join(ROOT, slug)
    if not os.path.isfile(os.path.join(d, "colors.toml")):
        continue
    colors = tomllib.load(open(os.path.join(d, "colors.toml"), "rb"))
    k = conf(os.path.join(d, "kde.conf"))
    bgs = sorted(f for f in os.listdir(os.path.join(d, "backgrounds"))) if os.path.isdir(os.path.join(d, "backgrounds")) else []
    src = os.path.join(d, "backgrounds", bgs[0]) if bgs else os.path.join(d, "preview.png")
    thumb = os.path.join(d, "thumb.jpg")
    if os.path.isfile(src) and (not os.path.isfile(thumb) or os.path.getmtime(thumb) < os.path.getmtime(src)):
        subprocess.run(["magick", src, "-resize", "480x300^", "-gravity", "center", "-extent", "480x300",
                        "-quality", "82", thumb], check=True)
    files = []
    for base, _, names in os.walk(d):
        for n in sorted(names):
            rel = os.path.relpath(os.path.join(base, n), d)
            if rel != "thumb.jpg":
                files.append(rel)
    themes.append({"slug": slug, "name": k.get("NAME") or " ".join(w.capitalize() for w in slug.split("-")),
                   "mode": colors.get("mode", "dark"), "animation": k.get("ANIMATION", ""),
                   "colors": [colors[c] for c in ("background", "accent", "red", "green", "yellow", "blue", "magenta", "cyan") if c in colors],
                   "thumb": "thumb.jpg", "files": sorted(files),
                   "size": sum(os.path.getsize(os.path.join(d, f)) for f in files)})
json.dump({"version": 1, "themes": themes}, open(os.path.join(ROOT, "index.json"), "w"), indent=1, ensure_ascii=False)
print(f"{len(themes)} themes")
