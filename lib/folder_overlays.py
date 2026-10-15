#!/usr/bin/python3 -I
"""Create a small overlay icon theme per folder color (e.g. Papirus-Dark-teal).

It only contains links to Papirus' colored folder icons and inherits everything else
from Papirus-Dark / Papirus-Light. A theme switch then only changes the icon theme
instead of rewriting thousands of links (papirus-folders).
Usage: folder_overlays.py [color ...]   (no argument: all colors used by installed themes)
"""
import configparser
import os
import re
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from plasmarchy_common import XDG_DATA, load_kde_conf, themes  # noqa: E402

ICONS = os.path.join(XDG_DATA, "icons")      # overlays always go to the user's directory
# Papirus itself: prefer a per-user install, otherwise system-wide (package papirus-icon-theme)
PAPIRUS = next((p for p in (os.path.join(ICONS, "Papirus"), "/usr/share/icons/Papirus")
                if os.path.isfile(os.path.join(p, "index.theme"))), os.path.join(ICONS, "Papirus"))
SAFE_ALIAS = re.compile(r"^(folder.*|user-.*|inode-directory|gtk-directory|stock_folder|stock_open)\.svg$")


def theme_colors():
    return sorted({load_kde_conf(slug).get("FOLDER_COLOR") for slug in themes()} - {None, ""})


def places_dirs():
    idx = configparser.ConfigParser(interpolation=None, strict=False)
    idx.optionxform = str
    idx.read(os.path.join(PAPIRUS, "index.theme"))
    head = idx["Icon Theme"]
    # @2x variants (for scaled displays) are listed separately under ScaledDirectories
    scaled = [d for d in head.get("ScaledDirectories", "").split(",") if d]
    return idx, head["Directories"].split(",") + scaled


def build(variant, color, idx, dirs):
    name = f"{variant}-{color}"
    out = os.path.join(ICONS, name)
    shutil.rmtree(out, ignore_errors=True)
    pattern = re.compile(rf"^(folder|user)-{re.escape(color)}(-.*)?\.svg$")
    # 1) default names (folder.svg, folder-documents.svg, user-home.svg ...) -> colored variant
    redirect = {}   # Papirus path of the default name -> colored target file
    for d in dirs:
        src = os.path.join(PAPIRUS, d)
        if d.endswith("/places") and os.path.isdir(src):
            for f in os.listdir(src):
                m = pattern.match(f)
                if m:
                    default = f"{m.group(1)}{m.group(2) or ''}.svg"
                    redirect[os.path.normpath(os.path.join(src, default))] = os.path.join(src, f)
    # 2) aliases pointing at default names (inode-directory -> folder.svg, folder-new ...), in all contexts
    changed = True
    while changed:
        changed = False
        for d in dirs:
            src = os.path.join(PAPIRUS, d)
            if not os.path.isdir(src):
                continue
            for f in os.listdir(src):
                path = os.path.normpath(os.path.join(src, f))
                if path in redirect or not os.path.islink(path):
                    continue
                # Real folder names only - generic names like "network" or "desktop" would otherwise
                # replace other icons through KDE's dash fallback (e.g. the Wi-Fi icon in the tray)
                if not SAFE_ALIAS.match(f):
                    continue
                target = os.path.normpath(os.path.join(src, os.readlink(path)))
                if target in redirect:
                    redirect[path] = redirect[target]
                    changed = True
    used = set()
    for path, target in redirect.items():
        d = os.path.relpath(os.path.dirname(path), PAPIRUS)
        os.makedirs(os.path.join(out, d), exist_ok=True)
        os.symlink(target, os.path.join(out, d, os.path.basename(path)))
        used.add(d)
    plain = [d for d in idx["Icon Theme"]["Directories"].split(",") if d in used]
    scaled = [d for d in dirs if d in used and d not in plain]
    used = plain + scaled
    lines = ["[Icon Theme]", f"Name={name}", f"Comment=Folder color {color} for {variant}",
             f"Inherits={variant},breeze,hicolor", "Hidden=true",
             f"Directories={','.join(plain)}", f"ScaledDirectories={','.join(scaled)}", ""]
    for d in used:
        lines.append(f"[{d}]")
        lines += [f"{k}={v}" for k, v in idx[d].items()]
        lines.append("")
    with open(os.path.join(out, "index.theme"), "w") as fh:
        fh.write("\n".join(lines))
    return name


def main():
    idx, dirs = places_dirs()
    for color in sys.argv[1:] or theme_colors():
        for variant in ("Papirus-Dark", "Papirus-Light"):
            print(build(variant, color, idx, dirs))


if __name__ == "__main__":
    main()
