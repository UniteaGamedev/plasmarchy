#!/usr/bin/python3 -I
"""Minimal translation layer for Plasmarchy.

English is the source language. Translations live in lib/locale/<lang>.json as {"English text": "Translation"}.
The language follows the system (LANGUAGE / LC_ALL / LC_MESSAGES / LANG); unknown languages fall back to English.

  from i18n import tr            tr("Theme: {0}", slug)
  i18n.py tr "<text>" [args...]  same, for shell scripts
  i18n.py lang                   active language code (e.g. "de" or "pt_BR")
  i18n.py build-mo <lang> <out.mo> [domain-prefix]
                                 compile the catalog into a gettext .mo file (used for the Plasma widget)
"""
import json
import os
import struct
import sys

LOCALE_DIR = os.path.join(os.path.dirname(os.path.realpath(__file__)), "locale")
_catalog = None


def locale_name():
    """Full locale of the user, e.g. "pt_BR" or "de" (from LANGUAGE / LC_ALL / LC_MESSAGES / LANG)."""
    for var in ("LANGUAGE", "LC_ALL", "LC_MESSAGES", "LANG"):
        value = os.environ.get(var, "")
        if value and value not in ("C", "POSIX"):
            loc = value.split(":")[0].split(".")[0].split("@")[0]
            lang, _, region = loc.partition("_")
            return f"{lang.lower()}_{region.upper()}" if region else lang.lower()
    return "en"


def language():
    """Two-letter language code, e.g. "pt" for pt_BR."""
    return locale_name().split("_")[0]


def catalog(lang=None):
    """Translations for the language - the regional catalog (pt_BR.json) wins, then the general one (pt.json)."""
    global _catalog
    lang = lang or locale_name()
    if _catalog is None or lang != _catalog[0]:
        data = {}
        for name in (lang.split("_")[0], lang):          # general first, regional entries override
            path = os.path.join(LOCALE_DIR, f"{name}.json")
            if name != "en" and os.path.isfile(path):
                data.update(json.load(open(path, encoding="utf-8")))
        _catalog = (lang, data)
    return _catalog[1]


def tr(text, *args):
    s = catalog().get(text, text)
    return s.format(*args) if args else s


def build_mo(lang, out):
    """Write a GNU gettext .mo file from the JSON catalog (no gettext tools needed)."""
    data = {}
    for name in dict.fromkeys((lang.split("_")[0], lang)):   # regional catalogs build on the general one
        path = os.path.join(LOCALE_DIR, f"{name}.json")
        if os.path.isfile(path):
            data.update(json.load(open(path, encoding="utf-8")))
    entries = sorted((k.encode(), v.encode()) for k, v in data.items() if k and v)
    entries.insert(0, (b"", b"Content-Type: text/plain; charset=UTF-8\n"))
    n = len(entries)
    keys_start = 7 * 4
    values_start = keys_start + n * 8
    data_start = values_start + n * 8
    offsets, blob = [], b""
    for k, _ in entries:
        offsets.append((len(k), data_start + len(blob)))
        blob += k + b"\0"
    voffsets = []
    for _, v in entries:
        voffsets.append((len(v), data_start + len(blob)))
        blob += v + b"\0"
    header = struct.pack("<7I", 0x950412DE, 0, n, keys_start, values_start, 0, 0)
    table = b"".join(struct.pack("<2I", *o) for o in offsets) + b"".join(struct.pack("<2I", *o) for o in voffsets)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "wb") as f:
        f.write(header + table + blob)


if __name__ == "__main__":
    a = sys.argv[1:]
    if a and a[0] == "tr":
        print(tr(a[1], *a[2:]))
    elif a and a[0] == "lang":
        print(locale_name())
    elif a and a[0] == "build-mo":
        build_mo(a[1], a[2])
    else:
        raise SystemExit(__doc__)
