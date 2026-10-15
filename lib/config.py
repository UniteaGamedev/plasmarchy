#!/usr/bin/python3 -I
"""Central Plasmarchy settings (backend of the "Plasmarchy" page in System Settings).

  config.py get                 all settings as JSON
  config.py set <key> <value>   change one setting and apply it right away

Keys: wallpaper.override (image path or empty), animated.mode (auto|on|off), animated.effect, animated.logo (on|off),
      branding.text, branding.image, menu.style (plasmarchy|kde), font.ui / font.mono ("Family,size"),
      player (on|off), hotcorner (on|off), screensaver.timeout (minutes, 0 = off)
"""
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import animated  # noqa: E402
import branding  # noqa: E402
from i18n import tr  # noqa: E402
from plasmarchy_common import XDG_CONFIG, current_theme, display_name  # noqa: E402

CONF_DIR = os.path.join(XDG_CONFIG, "plasmarchy")
WALLPAPER_CONF = os.path.join(CONF_DIR, "wallpaper.conf")
SCREENSAVER_CONF = os.path.join(CONF_DIR, "screensaver.conf")
BIN = os.path.expanduser("~/.local/bin/plasmarchy")
LIB = os.path.dirname(os.path.realpath(__file__))
DEFAULT_UI_FONT = "Noto Sans,10"
DEFAULT_MONO_FONT = "JetBrainsMono Nerd Font,10"


def read_kv(path):
    c = {}
    try:
        for line in open(path):
            if "=" in line and not line.lstrip().startswith("#"):
                k, v = line.strip().split("=", 1)
                c[k.strip()] = v.strip().strip('"')
    except OSError:
        pass
    return c


def write_kv(path, key, value, header=""):
    lines = open(path).read().splitlines() if os.path.isfile(path) else ([header] if header else [])
    lines = [l for l in lines if not l.strip().startswith(key + "=")] + [f'{key}="{value}"' if " " in value else f"{key}={value}"]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w").write("\n".join(lines) + "\n")


def kread(file, group, key, default=""):
    out = subprocess.run(["kreadconfig6", "--file", file, "--group", group, "--key", key],
                         capture_output=True, text=True).stdout.strip()
    return out or default


def kwrite(file, group, key, value):
    subprocess.run(["kwriteconfig6", "--file", file, "--group", group, "--key", key, value], check=False)


def short_font(qt):
    """'Noto Sans,10,-1,5,...' -> 'Noto Sans,10'"""
    parts = (qt or "").split(",")
    return f"{parts[0]},{parts[1]}" if len(parts) > 1 else ""


def qt_font(short):
    family, size = (short.rsplit(",", 1) + ["10"])[:2]
    size = size.strip() if size.strip().replace(".", "").isdigit() else "10"
    return f"{family.strip()},{size},-1,5,400,0,0,0,0,0,0,0,0,0,0,1"


def menu_style():
    out = subprocess.run(["qdbus6", "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript",
                          'var r="";panels().forEach(p=>p.widgets().forEach(w=>{if(w.type=="org.kde.plasma.kickoff")r="kde";'
                          'if(w.type=="org.plasmarchy.menu")r="plasmarchy"}));print(r)'], capture_output=True, text=True).stdout
    return out.strip() or "plasmarchy"


def get():
    slug = current_theme()
    wp = read_kv(WALLPAPER_CONF)
    ac = animated.conf()
    return {
        "theme": {"slug": slug, "name": display_name(slug)},
        "wallpaper": {"override": wp.get("OVERRIDE", ""), "animatedMode": ac["ANIMATED"], "effect": ac["EFFECT"] or "aurora",
                      "showLogo": ac["SHOW_LOGO"] != "off", "logoStyle": ac["LOGO_STYLE"],
                      "themeAnimation": animated.effect_for(slug)},
        "branding": branding.info(),
        "menuStyle": menu_style(),
        "fonts": {"ui": short_font(kread("kdeglobals", "General", "font")) or DEFAULT_UI_FONT,
                  "mono": short_font(kread("kdeglobals", "General", "fixed")) or DEFAULT_MONO_FONT},
        "player": "PLAYER=off" not in (open(os.path.join(CONF_DIR, "topbar.conf")).read()
                                       if os.path.isfile(os.path.join(CONF_DIR, "topbar.conf")) else ""),
        "hotcorner": kread("kwinrc", "Effect-overview", "BorderActivate", "9") == "9",
        "screensaverTimeout": int(read_kv(SCREENSAVER_CONF).get("TIMEOUT_MIN", "5") or 0),
        "effects": [{"id": e, "name": tr(n)} for e, n in (("aurora", "Aurora"), ("particles", "Particles"),
                                                          ("rain", "Code rain"), ("logo", "Logo animation"))],
    }


def reapply_theme():
    state = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")), "plasmarchy", "current")
    idx = "0"
    try:
        idx = open(state).read().splitlines()[1]
    except (OSError, IndexError):
        pass
    subprocess.run([BIN, "theme", current_theme(), idx], stdout=subprocess.DEVNULL, check=False)


def notify_fonts():
    # same signal the KDE font settings send: running apps pick up the new font
    subprocess.run(["dbus-send", "--session", "--type=signal", "/KGlobalSettings", "org.kde.KGlobalSettings.notifyChange",
                    "int32:1", "int32:0"], check=False)


def set_value(key, value):
    if key == "wallpaper.override":
        if value and not os.path.isfile(value):
            raise SystemExit(tr("File not found: {0}", value))
        write_kv(WALLPAPER_CONF, "OVERRIDE", value)
        reapply_theme()
    elif key == "animated.mode":
        animated.set_conf("ANIMATED", value)
        reapply_theme()
    elif key == "animated.effect":
        animated.set_conf("EFFECT", value)
        reapply_theme()
    elif key == "animated.logo":
        animated.set_conf("SHOW_LOGO", value)
        reapply_theme()
    elif key == "animated.logostyle":
        animated.set_conf("LOGO_STYLE", "animated" if value == "animated" else "glow")
        reapply_theme()
    elif key == "branding.text":
        branding.from_text(value)
        subprocess.run([sys.executable, "-I", os.path.join(LIB, "animated.py"), "refresh"], check=False)
    elif key == "branding.image":
        branding.from_image(value)
        subprocess.run([sys.executable, "-I", os.path.join(LIB, "animated.py"), "refresh"], check=False)
    elif key == "menu.style":
        subprocess.run([sys.executable, "-I", os.path.join(LIB, "layout.py"), "launcher", value], check=False)
    elif key in ("font.ui", "font.mono"):
        f = qt_font(value)
        if key == "font.ui":
            for k in ("font", "menuFont", "toolBarFont"):
                kwrite("kdeglobals", "General", k, f)
            kwrite("kdeglobals", "WM", "activeFont", f)
            family, size = (value.rsplit(",", 1) + ["10"])[:2]
            kwrite("kdeglobals", "General", "smallestReadableFont", qt_font(f"{family},{max(6, int(float(size)) - 2)}"))
        else:
            kwrite("kdeglobals", "General", "fixed", f)
        notify_fonts()
    elif key == "player":
        subprocess.run([sys.executable, "-I", os.path.join(LIB, "layout.py"), "player", value],
                       stdout=subprocess.DEVNULL, check=False)
    elif key == "hotcorner":
        kwrite("kwinrc", "Effect-overview", "BorderActivate", "9" if value == "on" else "99")
        subprocess.run(["qdbus6", "org.kde.KWin", "/KWin", "reconfigure"], capture_output=True)
    elif key == "screensaver.timeout":
        write_kv(SCREENSAVER_CONF, "TIMEOUT_MIN", str(int(value)))
        subprocess.run(["systemctl", "--user", "restart", "plasmarchy-idle.service"], capture_output=True)
    else:
        raise SystemExit(tr("Unknown setting: {0}", key))
    return {"ok": True}


def main():
    a = sys.argv[1:]
    if a[:1] == ["get"] or not a:
        print(json.dumps(get(), ensure_ascii=False))
    elif a[:1] == ["set"] and len(a) >= 2:
        print(json.dumps(set_value(a[1], " ".join(a[2:]))))
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
