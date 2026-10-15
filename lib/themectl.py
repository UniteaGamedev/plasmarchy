#!/usr/bin/python3 -I
"""Theme management for the plasmarchy script (called from bash).

  themectl.py path <slug>                  theme directory
  themectl.py backgrounds <slug>           wallpapers, one per line
  themectl.py info <slug>                  mode=..., folder=..., name=...
  themectl.py list                         slug<TAB>name<TAB>custom|built-in
  themectl.py new <name> [template]        create a custom theme from a template, prints the slug
  themectl.py save <slug> <file.json>      save a custom theme from JSON (used by the Theme Studio)
  themectl.py delete <slug>                delete a custom theme (built-in themes are protected)
"""
import json
import os
import re
import shutil
import sys
import unicodedata

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from plasmarchy_common import (FOLDER_COLORS, PALETTE_KEYS, USER_THEMES, XDG_DATA, backgrounds,  # noqa: E402
                               display_name, is_builtin_theme, is_user_theme, load_colors, load_kde_conf,
                               scheme_id, theme_dir, themes)
from i18n import tr  # noqa: E402

HEX = re.compile(r"^#[0-9a-fA-F]{6}$")


def slugify(name):
    s = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode().lower()
    s = re.sub(r"[^a-z0-9]+", "-", s).strip("-")
    return s or "theme"


def unique_slug(name):
    base = slugify(name)
    slug, n = base, 2
    while slug in themes():
        slug, n = f"{base}-{n}", n + 1
    return slug


def write_theme(slug, name, mode, folder, palette, bgs):
    if mode not in ("dark", "light"):
        raise SystemExit(tr("mode must be dark or light"))
    if folder not in FOLDER_COLORS:
        raise SystemExit(tr("Unknown folder color: {0}", folder))
    bad = [k for k, v in palette.items() if k in PALETTE_KEYS and not HEX.match(v)]
    if bad:
        raise SystemExit(tr("Invalid colors: {0} (expected #rrggbb)", ", ".join(bad)))
    d = os.path.join(USER_THEMES, slug)
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "colors.toml"), "w") as f:
        f.write(f'mode = "{mode}"\n\n')
        for k in PALETTE_KEYS:
            if k in palette:
                f.write(f'{k} = "{palette[k]}"\n')
    with open(os.path.join(d, "kde.conf"), "w") as f:
        f.write(f'NAME="{name}"\nFOLDER_COLOR={folder}\n')
    with open(os.path.join(d, "backgrounds.list"), "w") as f:
        f.write("".join(os.path.expanduser(b) + "\n" for b in bgs if os.path.isfile(os.path.expanduser(b))))
    return slug


def cmd_new(name, template="osaka-jade"):
    c = load_colors(template)
    slug = unique_slug(name)
    write_theme(slug, name, c["mode"], load_kde_conf(template).get("FOLDER_COLOR", "blue"),
                {k: c[k] for k in PALETTE_KEYS if k in c}, backgrounds(template))
    print(slug)


def cmd_save(slug, path):
    data = json.load(open(path))
    if not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", slug or ""):
        slug = unique_slug(data.get("name") or "theme")   # only allow safe directory names
    # Fill in missing colors from the existing theme (or Osaka Jade) - never write an incomplete theme
    base = load_colors(slug if slug in themes() else "osaka-jade")
    data["palette"] = {**{k: base[k] for k in PALETTE_KEYS if k in base}, **data.get("palette", {})}
    if is_builtin_theme(slug) and not is_user_theme(slug):
        # Built-in themes stay untouched: changes are saved as a custom copy
        slug = unique_slug(data.get("name") or display_name(slug))
    write_theme(slug, data.get("name") or display_name(slug), data.get("mode", "dark"),
                data.get("folder", "blue"), data.get("palette", {}), data.get("backgrounds", []))
    print(slug)


def cmd_delete(slug):
    if not is_user_theme(slug):
        raise SystemExit(tr("'{0}' is a built-in theme and cannot be deleted", slug))
    shutil.rmtree(os.path.join(USER_THEMES, slug))
    for f in (os.path.join(XDG_DATA, "color-schemes", scheme_id(slug) + ".colors"),
              os.path.join(XDG_DATA, "konsole", scheme_id(slug) + ".colorscheme")):
        if os.path.exists(f) and not is_builtin_theme(slug):
            os.remove(f)
    print(slug)


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    cmd, args = sys.argv[1], sys.argv[2:]
    if cmd == "path":
        print(theme_dir(args[0]))
    elif cmd == "backgrounds":
        print("\n".join(backgrounds(args[0])))
    elif cmd == "info":
        c = load_colors(args[0])
        print(f"mode={c['mode']}\nfolder={load_kde_conf(args[0]).get('FOLDER_COLOR', '')}\nname={display_name(args[0])}")
    elif cmd == "list":
        for slug in themes():
            print(f"{slug}\t{display_name(slug)}\t{tr('custom') if is_user_theme(slug) else tr('built-in')}")
    elif cmd == "new":
        cmd_new(*args[:2])
    elif cmd == "save":
        cmd_save(*args[:2])
    elif cmd == "delete":
        cmd_delete(args[0])
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
