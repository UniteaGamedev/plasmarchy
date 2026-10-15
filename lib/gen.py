#!/usr/bin/python3 -I
"""Generate KDE and Konsole color schemes from theme palettes (colors.toml).

KDE:     ~/.local/share/color-schemes/Plasmarchy<Name>.colors
Konsole: ~/.local/share/konsole/Plasmarchy<Name>.colorscheme
Usage:   gen.py [theme ...]   (no argument: all themes)
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from plasmarchy_common import XDG_DATA, display_name, load_colors, scheme_id, themes  # noqa: E402

KDE_DIR = os.path.join(XDG_DATA, "color-schemes")
KONSOLE_DIR = os.path.join(XDG_DATA, "konsole")


def rgb(hex_color):
    h = hex_color.lstrip("#")
    return ",".join(str(int(h[i:i + 2], 16)) for i in (0, 2, 4))


def luminance(hex_color):
    r, g, b = (int(hex_color.lstrip("#")[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def kde_scheme(slug, c):
    light = c.get("mode") == "light"
    # Text on accent/selection: dark or light depending on the accent's brightness
    on_accent = c["darker_background"] if luminance(c["accent"]) > 0.45 else c["bright_foreground"]
    if light:
        on_accent = c["darker_background"] if luminance(c["accent"]) > 0.6 else "#ffffff"

    def group(bg, bg_alt, fg=c["foreground"]):
        return {
            "BackgroundNormal": bg,
            "BackgroundAlternate": bg_alt,
            "DecorationFocus": c["accent"],
            "DecorationHover": c["accent"],
            "ForegroundNormal": fg,
            "ForegroundInactive": c["muted"],
            "ForegroundActive": c["accent"],
            "ForegroundLink": c["blue"],
            "ForegroundVisited": c["magenta"],
            "ForegroundNegative": c["red"],
            "ForegroundNeutral": c["orange"],
            "ForegroundPositive": c["green"],
        }

    groups = {
        "Colors:Window": group(c["background"], c["dark_background"]),
        "Colors:View": group(c["dark_background"], c["background"]),
        "Colors:Button": group(c["lighter_background"], c["selection"]),
        "Colors:Selection": group(c["accent"], c["selection"], on_accent),
        "Colors:Tooltip": group(c["darker_background"], c["dark_background"]),
        "Colors:Complementary": group(c["darker_background"], c["dark_background"]),
        "Colors:Header": group(c["dark_background"], c["background"]),
        "Colors:Header][Inactive": group(c["dark_background"], c["background"]),
    }
    groups["Colors:Selection"]["ForegroundActive"] = on_accent

    out = []
    for name, keys in groups.items():
        out.append(f"[{name}]")
        out += [f"{k}={rgb(v)}" for k, v in keys.items()]
        out.append("")
    out += [
        "[General]",
        f"ColorScheme={scheme_id(slug)}",
        f"Name=Plasmarchy {display_name(slug)}",
        "shadeSortColumn=true",
        "",
        "[KDE]",
        "contrast=4",
        "",
        "[WM]",
        f"activeBackground={rgb(c['darker_background'])}",
        f"activeBlend={rgb(c['darker_background'])}",
        f"activeForeground={rgb(c['foreground'])}",
        f"inactiveBackground={rgb(c['darker_background'])}",
        f"inactiveBlend={rgb(c['darker_background'])}",
        f"inactiveForeground={rgb(c['muted'])}",
        "",
    ]
    return "\n".join(out)


def konsole_scheme(slug, c):
    pal = [
        ("Background", c["background"]), ("BackgroundIntense", c["dark_background"]),
        ("BackgroundFaint", c["background"]),
        ("Foreground", c["foreground"]), ("ForegroundIntense", c["bright_foreground"]),
        ("ForegroundFaint", c["muted"]),
    ]
    normal = [c["lighter_background"], c["red"], c["green"], c["yellow"], c["blue"], c["magenta"], c["cyan"], c["foreground"]]
    bright = [c["muted"], c["bright_red"], c["bright_green"], c["bright_yellow"], c["bright_blue"], c["bright_magenta"], c["bright_cyan"], c["bright_foreground"]]
    for i, (n, b) in enumerate(zip(normal, bright)):
        pal += [(f"Color{i}", n), (f"Color{i}Intense", b), (f"Color{i}Faint", n)]
    out = []
    for name, col in pal:
        out += [f"[{name}]", f"Color={rgb(col)}", ""]
    out += ["[General]", f"Description=Plasmarchy {display_name(slug)}", "Opacity=1", "Wallpaper=", ""]
    return "\n".join(out)


def main():
    os.makedirs(KDE_DIR, exist_ok=True)
    os.makedirs(KONSOLE_DIR, exist_ok=True)
    for slug in sys.argv[1:] or list(themes()):
        c = load_colors(slug)
        sid = scheme_id(slug)
        with open(os.path.join(KDE_DIR, sid + ".colors"), "w") as f:
            f.write(kde_scheme(slug, c))
        with open(os.path.join(KONSOLE_DIR, sid + ".colorscheme"), "w") as f:
            f.write(konsole_scheme(slug, c))
        print(f"{slug}\t{sid}\t{display_name(slug)}\t{c['mode']}")


if __name__ == "__main__":
    main()
