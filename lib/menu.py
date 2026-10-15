#!/usr/bin/python3 -I
"""Data for the Plasmarchy menu (menu.qml), modeled on Omarchy's menu: main entries with sub menus,
plus all installed apps for searching. Labels are translated; commands are shell snippets run by
"plasmarchy menu".

  menu.py <out.json>     write the menu (apps are cached and refreshed when application folders change)
"""
import configparser
import glob
import json
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from i18n import tr  # noqa: E402
from plasmarchy_common import current_colors  # noqa: E402

HOME = os.path.expanduser("~")
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.join(HOME, ".cache")), "plasmarchy")
APP_DIRS = [os.path.join(os.environ.get("XDG_DATA_HOME", os.path.join(HOME, ".local/share")), "applications"),
            "/usr/share/applications", "/var/lib/flatpak/exports/share/applications",
            os.path.join(HOME, ".local/share/flatpak/exports/share/applications")]
P = os.path.expanduser("~/.local/bin/plasmarchy")   # absolute: Plasma's PATH lacks ~/.local/bin


def kcm(name):
    return f"systemsettings {name}"


def menu():
    """Main menu. Items: {id, icon (Nerd Font glyph), label, cmd | items}."""
    g = lambda cp: chr(cp)  # noqa: E731  (Material Design glyphs from the Nerd Font)
    items = [
        {"id": "apps", "icon": g(0xF003B), "label": tr("Apps"), "apps": True},
        {"id": "learn", "icon": g(0xF09D1), "label": tr("Learn"), "items": [
            {"id": "keys", "icon": g(0xF030C), "label": tr("Keyboard shortcuts"), "cmd": kcm("kcm_keys")},
            {"id": "plasmarchy", "icon": g(0xF02D7), "label": "Plasmarchy",
             "cmd": "xdg-open https://github.com/UniteaGamedev/plasmarchy"},
            {"id": "kde", "icon": g(0xF0AB4), "label": tr("KDE user guide"), "cmd": "xdg-open https://userbase.kde.org"},
            {"id": "archwiki", "icon": g(0xF08C7), "label": "Arch Wiki", "cmd": "xdg-open https://wiki.archlinux.org"},
            {"id": "cachyos", "icon": g(0xF08C7), "label": "CachyOS Wiki", "cmd": "xdg-open https://wiki.cachyos.org"},
        ]},
        {"id": "toggle", "icon": g(0xF0521), "label": tr("Toggle"), "items": [
            {"id": "screensaver", "icon": g(0xF0379), "label": tr("Screensaver"), "cmd": f"{P} screensaver"},
            {"id": "player", "icon": g(0xF075A), "label": tr("Music player in the top bar"), "cmd": f"{P} toggle player"},
            {"id": "animated", "icon": g(0xF0E09), "label": tr("Animated wallpaper"), "cmd": f"{P} toggle animated"},
            {"id": "nightlight", "icon": g(0xF0594), "label": tr("Night light"), "cmd": f"{P} toggle nightlight"},
            {"id": "idle", "icon": g(0xF04B2), "label": tr("Automatic screensaver"), "cmd": f"{P} toggle idle"},
        ]},
        {"id": "style", "icon": g(0xF03D8), "label": tr("Style"), "items": [
            {"id": "theme", "icon": g(0xF03D8), "label": tr("Switch theme"), "cmd": f"{P} pick", "boost": 30,
             "keywords": "theme design look colors farben"},
            {"id": "studio", "icon": g(0xF00E3), "label": "Theme Studio", "cmd": f"{P} studio", "boost": 10,
             "keywords": "theme editor colors farben"},
            {"id": "background", "icon": g(0xF0E09), "label": tr("Next wallpaper"), "cmd": f"{P} next-bg"},
            {"id": "logo-text", "icon": g(0xF0284), "label": tr("Logo: text …"), "cmd": f"{P} branding ask-text"},
            {"id": "logo-image", "icon": g(0xF02E9), "label": tr("Logo: image …"), "cmd": f"{P} branding ask-image"},
            {"id": "logo-edit", "icon": g(0xF03EB), "label": tr("Logo: edit ASCII art"), "cmd": f"{P} branding edit"},
        ]},
        {"id": "capture", "icon": g(0xF0100), "label": tr("Capture"), "items": [
            {"id": "shot-region", "icon": g(0xF0100), "label": tr("Screenshot of an area"), "cmd": "spectacle -r"},
            {"id": "shot-screen", "icon": g(0xF0379), "label": tr("Screenshot of the screen"), "cmd": "spectacle -f"},
            {"id": "shot-window", "icon": g(0xF05B5), "label": tr("Screenshot of the window"), "cmd": "spectacle -a"},
            {"id": "rec-region", "icon": g(0xF044A), "label": tr("Record an area"), "cmd": "spectacle -R region"},
            {"id": "rec-screen", "icon": g(0xF044A), "label": tr("Record the screen"), "cmd": "spectacle -R screen"},
        ]},
        {"id": "setup", "icon": g(0xF0493), "label": tr("Setup"), "items": [
            {"id": "wifi", "icon": g(0xF05A9), "label": tr("Wi-Fi"), "cmd": kcm("kcm_networkmanagement")},
            {"id": "bluetooth", "icon": g(0xF00AF), "label": "Bluetooth", "cmd": kcm("kcm_bluetooth")},
            {"id": "audio", "icon": g(0xF057E), "label": tr("Audio"), "cmd": kcm("kcm_pulseaudio")},
            {"id": "display", "icon": g(0xF0379), "label": tr("Displays"), "cmd": kcm("kcm_kscreen")},
            {"id": "power", "icon": g(0xF0084), "label": tr("Power"), "cmd": kcm("kcm_powerdevilprofilesconfig")},
            {"id": "notifications", "icon": g(0xF009A), "label": tr("Notifications"), "cmd": kcm("kcm_notifications")},
            {"id": "nightlight-setup", "icon": g(0xF0594), "label": tr("Night light"), "cmd": kcm("kcm_nightlight")},
            {"id": "settings", "icon": g(0xF0493), "label": tr("All settings"), "cmd": "systemsettings"},
        ]},
        {"id": "ai", "icon": g(0xF06A9), "label": tr("AI assistant"), "items": [
            {"id": "ai-open", "icon": g(0xF0B79), "label": tr("Open chat"), "cmd": f"{P} assistant open"},
            {"id": "ai-talk", "icon": g(0xF036C), "label": tr("Talk"), "cmd": f"{P} talk"},
            {"id": "ai-usage", "icon": g(0xF0128), "label": tr("Usage & limits"), "cmd": f"{P} assistant open"},
        ]},
        {"id": "software", "icon": g(0xF03D7), "label": tr("Software"), "items": [
            {"id": "update", "icon": g(0xF06B0), "label": tr("Update system"),
             "cmd": f"{P} terminal 'sudo pacman -Syu'"},
            *([{"id": "discover", "icon": g(0xF03D7), "label": tr("Install apps (Discover)"), "cmd": "plasma-discover"}]
              if shutil.which("plasma-discover") else []),
            {"id": "voice-setup", "icon": g(0xF036C), "label": tr("Set up voice"), "cmd": f"{P} terminal '{P} voice setup'"},
            {"id": "llm-setup", "icon": g(0xF06A9), "label": tr("Set up local AI"), "cmd": f"{P} terminal '{P} llm setup'"},
        ]},
        {"id": "about", "icon": g(0xF02FD), "label": tr("About"), "cmd": "kinfocenter"},
        {"id": "system", "icon": g(0xF0425), "label": tr("System"), "items": [
            {"id": "lock", "icon": g(0xF033E), "label": tr("Lock"), "cmd": "loginctl lock-session"},
            {"id": "suspend", "icon": g(0xF04B2), "label": tr("Suspend"), "cmd": "systemctl suspend"},
            {"id": "logout", "icon": g(0xF0343), "label": tr("Log out"),
             "cmd": "qdbus6 org.kde.Shutdown /Shutdown org.kde.Shutdown.logout"},
            {"id": "restart", "icon": g(0xF0709), "label": tr("Restart"),
             "cmd": "qdbus6 org.kde.Shutdown /Shutdown org.kde.Shutdown.logoutAndReboot"},
            {"id": "shutdown", "icon": g(0xF0425), "label": tr("Shut down"),
             "cmd": "qdbus6 org.kde.Shutdown /Shutdown org.kde.Shutdown.logoutAndShutdown"},
        ]},
    ]
    return items


def apps():
    """Installed apps, cached; refreshed when an application folder changes."""
    cache = os.path.join(CACHE, "menu-apps.json")
    stamp = max((os.path.getmtime(d) for d in APP_DIRS if os.path.isdir(d)), default=0)
    try:
        if os.path.getmtime(cache) >= stamp:
            return json.load(open(cache))
    except (OSError, ValueError):
        pass
    lang = os.environ.get("LANG", "en").split(".")[0]
    seen, result = set(), []
    for d in APP_DIRS:
        for f in sorted(glob.glob(os.path.join(d, "**", "*.desktop"), recursive=True)):
            did = os.path.relpath(f, d).replace("/", "-")
            if did in seen or did.startswith("plasmarchy-"):   # user entries override system ones;
                continue                                         # our own entries are already in the menu
            seen.add(did)
            c = configparser.ConfigParser(interpolation=None, strict=False)
            c.optionxform = str
            try:
                c.read(f, encoding="utf-8")
                e = c["Desktop Entry"]
            except Exception:
                continue
            if e.get("Type") != "Application" or e.get("NoDisplay", "false").lower() == "true" \
                    or e.get("Hidden", "false").lower() == "true" or "OnlyShowIn" in e:
                continue
            name = e.get(f"Name[{lang}]") or e.get(f"Name[{lang.split('_')[0]}]") or e.get("Name", "")
            generic = e.get(f"GenericName[{lang.split('_')[0]}]") or e.get("GenericName", "")
            keywords = e.get(f"Keywords[{lang.split('_')[0]}]", "") + ";" + e.get("Keywords", "")
            if name:
                result.append({"id": "app:" + did, "label": name, "detail": generic, "iconName": e.get("Icon", ""),
                               "keywords": keywords.replace(";", " ").lower(),
                               "cmd": "kioclient exec " + json.dumps(f)})
    result.sort(key=lambda a: a["label"].lower())
    os.makedirs(CACHE, exist_ok=True)
    json.dump(result, open(cache, "w"))
    return result


def main():
    out = sys.argv[1]
    col = current_colors()
    json.dump({"menu": menu(), "apps": apps(),
               "colors": {k: col.get(k, "#888888") for k in ("background", "foreground", "accent", "muted")},
               "labels": {"search": tr("Search …"), "back": tr("Back"), "apps": tr("Apps"),
                          "krunner": tr("Search everywhere for “{0}”"), "empty": tr("Nothing found")}},
              open(out, "w"), ensure_ascii=False)


if __name__ == "__main__":
    main()
