#!/usr/bin/python3 -I
"""Write a theme overview as JSON for the theme picker and the Theme Studio.
Usage: manifest.py <output.json> [current-theme]
"""
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from plasmarchy_common import (CACHE, FOLDER_COLORS, PALETTE_KEYS, backgrounds, display_name,  # noqa: E402
                               is_builtin_theme, is_user_theme, load_colors, load_kde_conf, theme_dir, themes)

THUMBS = os.path.join(CACHE, "thumbs")


def thumbnail(src, slug):
    """Small preview image (some originals are 8K) - created once, then served from the cache."""
    out = os.path.join(THUMBS, slug + ".jpg")
    if not os.path.exists(out) or os.path.getmtime(out) < os.path.getmtime(src):
        os.makedirs(THUMBS, exist_ok=True)
        if subprocess.run(["magick", src, "-resize", "1200x800^", "-quality", "88", out],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0:
            return src
    return out


def main():
    out, current = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else "")
    result = []
    for slug in themes():
        c = load_colors(slug)
        bgs = backgrounds(slug)
        preview = bgs[0] if bgs else os.path.join(theme_dir(slug), "preview.png")
        result.append({
            "slug": slug,
            "name": display_name(slug),
            "image": thumbnail(preview, slug) if os.path.exists(preview) else "",
            "backgrounds": bgs,
            "light": c["mode"] == "light",
            "user": is_user_theme(slug),
            "builtin": is_builtin_theme(slug),
            "folder": load_kde_conf(slug).get("FOLDER_COLOR", "blue"),
            "palette": {k: c[k] for k in PALETTE_KEYS if k in c},
            "colors": [c[k] for k in ("background", "accent", "red", "green", "yellow", "blue", "magenta", "cyan") if k in c],
        })
    json.dump({"current": current, "folderColors": FOLDER_COLORS, "paletteKeys": PALETTE_KEYS, "themes": result},
              open(out, "w"))


if __name__ == "__main__":
    main()
