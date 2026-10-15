#!/usr/bin/python3 -I
"""Animated wallpapers (Plasma wallpaper plugin org.plasmarchy.animated).

Whether a theme gets an animated wallpaper:
  ~/.config/plasmarchy/wallpaper.conf  ANIMATED=auto  only themes that ship an animation (kde.conf ANIMATION=...)
                                       ANIMATED=on    every theme (themes without one get "aurora")
                                       ANIMATED=off   never

  animated.py effect-for <theme>   print the effect for a theme (empty = static wallpaper)
  animated.py apply <theme>        switch all desktops to the animation in the theme's colors (if any)
  animated.py toggle               animate the current theme or stop animating it
  animated.py refresh              reload the logo (after "plasmarchy branding")
  animated.py preview <theme> <out.png> [effect] [--no-logo]   render a still image (previews, lock screen)
"""
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from plasmarchy_common import BASE, XDG_CONFIG, current_theme, load_colors, load_kde_conf  # noqa: E402

PLUGIN = "org.plasmarchy.animated"
EFFECTS = ["aurora", "particles", "rain"]
CONF = os.path.join(XDG_CONFIG, "plasmarchy", "wallpaper.conf")
LOGO = os.path.join(XDG_CONFIG, "plasmarchy", "branding", "logo.png")
LIB = os.path.dirname(os.path.realpath(__file__))


def mode():
    try:
        for line in open(CONF):
            if line.startswith("ANIMATED="):
                return line.split("=", 1)[1].strip().strip('"') or "auto"
    except OSError:
        pass
    return "auto"


def set_mode(value):
    os.makedirs(os.path.dirname(CONF), exist_ok=True)
    open(CONF, "w").write("# Animated wallpapers: auto (themes that ship one) | on (every theme) | off\n"
                          f"ANIMATED={value}\n")


def effect_for(slug):
    m = mode()
    own = load_kde_conf(slug).get("ANIMATION", "")
    if m == "off":
        return ""
    if m == "on":
        return own if own in EFFECTS else "aurora"
    return own if own in EFFECTS else ""


def settings(slug, effect):
    c = load_colors(slug)
    keys = load_kde_conf(slug).get("ANIMATION_COLORS", "cyan blue magenta bright_cyan").split()
    return {"effect": effect, "background": c["background"],
            "darkBackground": c.get("darker_background", c["background"]),
            "foreground": c["foreground"], "accent": c["accent"],
            "palette": ",".join(c[k] for k in keys if k in c),
            "logo": LOGO if os.path.isfile(LOGO) else ""}


def evaluate(script):
    return subprocess.run(["qdbus6", "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript",
                           script], capture_output=True, text=True).stdout


def write_desktops(values, bump_logo=False):
    script = f"""
        var v = {json.dumps(values)};
        desktops().forEach(d => {{
            d.wallpaperPlugin = "{PLUGIN}";
            d.currentConfigGroup = ["Wallpaper", "{PLUGIN}", "General"];
            for (var k in v) d.writeConfig(k, v[k]);
            if ({'true' if bump_logo else 'false'}) d.writeConfig("logoVersion", Number(d.readConfig("logoVersion", 0)) + 1);
        }});
    """
    evaluate(script)


def apply(slug):
    effect = effect_for(slug)
    if effect:
        write_desktops(settings(slug, effect))
    print(effect)


def active():
    return evaluate(f'print(desktops().some(d => d.wallpaperPlugin == "{PLUGIN}") ? "yes" : "no")').strip() == "yes"


def preview(slug, out, effect=None, logo=True):
    """Still image of the animation (offscreen, GPU via OpenGL)."""
    s = settings(slug, effect or effect_for(slug) or "aurora")
    s["colorList"] = s.pop("palette").split(",")
    s["logo"] = "file://" + s["logo"] if s["logo"] else ""
    s["showLogo"] = bool(s["logo"]) and logo
    scene = os.path.join(BASE, "plasmoids", PLUGIN, "contents", "ui", "Scene.qml")
    if not os.path.isfile(scene):   # running from the repository
        scene = os.path.join(os.path.dirname(LIB), "plasmoids", PLUGIN, "contents", "ui", "Scene.qml")
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="rhi", QSG_RHI_BACKEND="opengl")
    size = subprocess.run(["sh", "-c", "cat ${XDG_CACHE_HOME:-$HOME/.cache}/plasmarchy/screen-size 2>/dev/null"],
                          capture_output=True, text=True).stdout.strip() or "2560x1600"
    w, h = size.split("x")
    subprocess.run(["/usr/lib/qt6/bin/qml", os.path.join(LIB, "wallpaper_preview.qml"), "--", "file://" + scene,
                    out, w, h, "12", json.dumps(s)], env=env, timeout=90, check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main():
    a = sys.argv[1:]
    cmd = a[0] if a else ""
    if cmd == "effect-for" and len(a) == 2:
        print(effect_for(a[1]))
    elif cmd == "apply" and len(a) == 2:
        apply(a[1])
    elif cmd == "toggle":
        if active():
            # Off: back to "auto" if the theme has no animation of its own, otherwise really off
            own = load_kde_conf(current_theme()).get("ANIMATION", "") in EFFECTS
            set_mode("off" if own else "auto")
            print("off")
        else:
            set_mode("on")
            print("on")
    elif cmd == "mode":
        if len(a) == 2 and a[1] in ("auto", "on", "off"):
            set_mode(a[1])
        print(mode())
    elif cmd == "refresh":
        if active():
            write_desktops(settings(current_theme(), effect_for(current_theme()) or "aurora"), bump_logo=True)
    elif cmd == "preview" and len(a) >= 3:
        rest = [x for x in a[3:] if x != "--no-logo"]
        preview(a[1], a[2], rest[0] if rest else None, logo="--no-logo" not in a)
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
