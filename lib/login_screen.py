#!/usr/bin/python3 -I
"""Login screen (Plasma Login Manager) in the look of the active theme.

  login_screen.py apply [theme]   wallpaper (animated like the desktop, or the theme's image) and colors
  login_screen.py reset           back to the login screen from before Plasmarchy
  login_screen.py status          "ready" if the system-wide helper is installed (install.sh), else "missing"

The login screen can't read files in the home directory, so everything is handed to a root helper
(/usr/local/lib/plasmarchy/login-screen) as data; polkit lets the logged-in user run it without a password.
"""
import base64
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from plasmarchy_common import XDG_CONFIG, XDG_DATA, current_theme, scheme_id  # noqa: E402
import animated  # noqa: E402

HELPER = "/usr/local/lib/plasmarchy/login-screen"


def ready():
    return os.access(HELPER, os.X_OK) and os.path.isfile("/etc/plasmalogin.conf")


def b64(path):
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode()


def scheme_colors(slug):
    """[Colors:*] and [WM] groups of the theme's generated color scheme ("r,g,b" values only)."""
    groups, group = {}, None
    path = os.path.join(XDG_DATA, "color-schemes", scheme_id(slug) + ".colors")
    for line in open(path):
        line = line.strip()
        if line.startswith("["):
            name = line[1:-1]
            group = name if (name.startswith("Colors:") and "][" not in name) or name == "WM" else None
        elif group and "=" in line:
            k, v = line.split("=", 1)
            if v.count(",") == 2:
                groups.setdefault(group, {})[k] = v
    return groups


def lock_screen_image():
    """The lock screen always shows a still image of the theme (set on every theme switch)."""
    url = subprocess.run(["kreadconfig6", "--file", "kscreenlockerrc", "--group", "Greeter", "--group", "Wallpaper",
                          "--group", "org.kde.image", "--group", "General", "--key", "Image"],
                         capture_output=True, text=True).stdout.strip()
    path = url.removeprefix("file://")
    return path if os.path.isfile(path) else ""


def own_wallpaper():
    try:
        for line in open(os.path.join(XDG_CONFIG, "plasmarchy", "wallpaper.conf")):
            if line.startswith("OVERRIDE="):
                path = line.split("=", 1)[1].strip().strip('"')
                return path if os.path.isfile(path) else ""
    except OSError:
        pass
    return ""


def payload(slug):
    p = {"colors": scheme_colors(slug)}
    effect = "" if own_wallpaper() else animated.effect_for(slug)
    if effect:
        cfg = animated.settings(slug, effect)
        logo = cfg.pop("logo")
        p.update(plugin=animated.PLUGIN, config=cfg, logo=b64(logo) if logo else "")
    else:
        image = lock_screen_image()
        if not image:
            raise SystemExit("login_screen: no wallpaper image found")
        p.update(plugin="org.kde.image", image=b64(image))
    return p


def helper(*args, data=None):
    r = subprocess.run(["pkexec", HELPER, *args], input=data, capture_output=True)
    if r.returncode:
        raise SystemExit(r.stderr.decode(errors="replace").strip() or f"login_screen: helper failed ({r.returncode})")


def main():
    a = sys.argv[1:]
    cmd = a[0] if a else ""
    if cmd == "status":
        print("ready" if ready() else "missing")
    elif cmd == "apply":
        if not ready():
            return   # not set up (install.sh --no-login-screen): leave the login screen alone
        helper("apply", data=json.dumps(payload(a[1] if len(a) > 1 else current_theme())).encode())
    elif cmd == "reset":
        if ready():
            helper("reset")
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
