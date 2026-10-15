#!/usr/bin/python3 -I
"""Translation maintenance for Plasmarchy.

English is the source language; translations live in lib/locale/<lang>.json ({"English": "Translation"}).

  tools/i18n.py strings                 print every translatable English string (one JSON list)
  tools/i18n.py check [lang]            missing / obsolete entries per language
  tools/i18n.py prune                   drop obsolete entries from all catalogs
  tools/i18n.py sync                    write Name[xx]/Comment[xx] into .desktop files and widget metadata

To add a language: copy lib/locale/de.json to <lang>.json (e.g. fr.json, pt_BR.json), translate the values,
run "tools/i18n.py check <lang>" and "tools/i18n.py sync".
"""
import ast
import glob
import json
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.realpath(__file__)), ".."))
LOCALE = os.path.join(ROOT, "lib", "locale")
# dicts whose values are passed through tr() at runtime
TRANSLATED_DICTS = {"assistant.py": ["MESSAGES"], "settings.py": ["VOICES", "MODELS", "WAKE_WORDS"],
                    "ai_usage.py": ["LIMIT_NAMES"]}


def files(*patterns):
    return sorted(f for p in patterns for f in glob.glob(os.path.join(ROOT, p), recursive=True))


def desktop_strings():
    """Name/GenericName/Comment of our .desktop files and Name/Description of the widgets' metadata."""
    out = []
    for f in files("applications/*.desktop", "systemsettings/*.desktop"):
        for line in open(f, encoding="utf-8"):
            m = re.match(r"(Name|GenericName|Comment)=(.+)$", line.strip())
            if m:
                out.append(m.group(2))
    for f in files("plasmoids/*/metadata.json"):
        k = json.load(open(f, encoding="utf-8"))["KPlugin"]
        out += [k[x] for x in ("Name", "Description") if x in k]
    return out


def strings():
    found = []

    def add(s):
        s = s.replace('\\"', '"').replace("\\n", "\n")
        if s and s not in found:
            found.append(s)
    for f in files("lib/*.py"):
        src = open(f, encoding="utf-8").read()
        for m in re.findall(r'\btr\(\s*"((?:[^"\\]|\\.)*)"', src):
            add(m)
        names = TRANSLATED_DICTS.get(os.path.basename(f), [])
        if names:
            for node in ast.walk(ast.parse(src)):
                if isinstance(node, ast.Assign) and any(getattr(t, "id", "") in names for t in node.targets):
                    for v in ast.literal_eval(node.value).values():
                        add(v)
    for f in files("lib/*.qml"):
        for m in re.findall(r'\btr\("((?:[^"\\]|\\.)*)"', open(f, encoding="utf-8").read()):
            add(m)
    for f in files("plasmoids/*/contents/ui/*.qml", "plasmoids/*/contents/config/*.qml"):
        for m in re.findall(r'\bi18n\("((?:[^"\\]|\\.)*)"', open(f, encoding="utf-8").read()):
            add(m)
    for f in [os.path.join(ROOT, p) for p in ("bin/plasmarchy", "install.sh", "uninstall.sh")]:
        src = open(f, encoding="utf-8").read()
        for m in re.findall(r'\bt "((?:[^"\\$]|\\.)*)"', src):
            add(m)
        for m in re.findall(r"t \"\$\(cat <<'EOF'\n(.*?)\nEOF\n\)\"", src, re.S):   # multi-line summaries
            add(m)
    for s in desktop_strings():
        add(s)
    # examples in docstrings are not real strings
    return [s for s in found if s not in ("Theme: {0}", "Text {0}")]


def catalogs():
    return {os.path.basename(f)[:-5]: f for f in files("lib/locale/*.json")}


def check(lang=None):
    src = set(strings())
    for name, path in sorted(catalogs().items()):
        if lang and name != lang:
            continue
        cat = json.load(open(path, encoding="utf-8"))
        missing = [s for s in strings() if s not in cat]
        obsolete = [k for k in cat if k not in src]
        print(f"{name}: {len(cat)} entries, {len(missing)} missing, {len(obsolete)} obsolete")
        for s in missing:
            print("  missing:", json.dumps(s, ensure_ascii=False))


def prune():
    src = set(strings())
    for path in catalogs().values():
        cat = json.load(open(path, encoding="utf-8"))
        cat = {k: v for k, v in sorted(cat.items()) if k in src}
        json.dump(cat, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
        open(path, "a").write("\n")


def sync():
    """Localized Name/Comment entries in .desktop files and metadata.json, generated from the catalogs."""
    cats = {k: json.load(open(v, encoding="utf-8")) for k, v in catalogs().items()}
    for f in files("applications/*.desktop", "systemsettings/*.desktop"):
        lines = [l for l in open(f, encoding="utf-8").read().splitlines()
                 if not re.match(r"(Name|GenericName|Comment)\[[^\]]+\]=", l)]
        out = []
        for line in lines:
            out.append(line)
            m = re.match(r"(Name|GenericName|Comment)=(.+)$", line)
            if m:
                out += [f"{m.group(1)}[{lang}]={cat[m.group(2)]}" for lang, cat in sorted(cats.items()) if m.group(2) in cat]
        open(f, "w", encoding="utf-8").write("\n".join(out) + "\n")
    for f in files("plasmoids/*/metadata.json"):
        d = json.load(open(f, encoding="utf-8"))
        k = d["KPlugin"]
        for key in [x for x in list(k) if re.match(r"(Name|Description)\[", x)]:
            del k[key]
        for field in ("Name", "Description"):
            if field in k:
                for lang, cat in sorted(cats.items()):
                    if k[field] in cat:
                        k[f"{field}[{lang}]"] = cat[k[field]]
        json.dump(d, open(f, "w", encoding="utf-8"), indent=4, ensure_ascii=False)
        open(f, "a").write("\n")


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["strings"]:
        print(json.dumps(strings(), ensure_ascii=False, indent=1))
    elif a[:1] == ["check"]:
        check(a[1] if len(a) > 1 else None)
    elif a[:1] == ["prune"]:
        prune()
    elif a[:1] == ["sync"]:
        sync()
    else:
        raise SystemExit(__doc__)
