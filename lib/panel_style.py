#!/usr/bin/python3 -I
"""Generate Panel Colorizer settings (globalSettings) for the Plasmarchy top bar and dock.

Based on Panel Colorizer's bundled "Default" preset; all colors are system colors
(sourceType 1), so the bar and dock follow every theme automatically.
Usage: panel_style.py top|dock   -> JSON on stdout
"""
import copy
import json
import os
import sys

PRESET = os.path.expanduser(
    "~/.local/share/plasma/plasmoids/luisbocanegra.panel.colorizer/contents/ui/presets/Default/settings.json")


def system_color(base, role, color_set, alpha):
    c = copy.deepcopy(base)
    c.update({"enabled": True, "sourceType": 1, "systemColor": role, "systemColorSet": color_set, "alpha": alpha})
    return c


def style(kind):
    g = json.load(open(PRESET))["globalSettings"]
    p = g["panel"]["normal"]
    bg = p["backgroundColor"]

    p["enabled"] = True
    p["blurBehind"] = True
    p["shadow"]["background"]["enabled"] = False
    p["padding"]["enabled"] = False

    if kind == "top":
        p["backgroundColor"] = system_color(bg, "backgroundColor", "Window", 0.94)
        p["radius"]["enabled"] = False
        p["margin"]["enabled"] = False
        b = p["border"]
        b.update({"enabled": True, "customSides": True, "width": 1})
        b["custom"]["widths"] = {"left": 0, "right": 0, "top": 0, "bottom": 1}
        b["color"] = system_color(b["color"], "textColor", "Window", 0.10)
        # Like Omarchy: all icons/text monochrome in the theme's text color
        for group in ("widgets", "trayWidgets"):
            w = g[group]["normal"]
            w["enabled"] = True
            w["foregroundColor"] = system_color(w["foregroundColor"], "textColor", "Window", 1)
    else:  # dock
        p["backgroundColor"] = system_color(bg, "backgroundColor", "Window", 0.62)
        r = 18
        p["radius"] = {"enabled": True, "corner": {"topLeft": r, "topRight": r, "bottomRight": r, "bottomLeft": r}}
        p["margin"] = {"enabled": True, "side": {"left": 0, "right": 0, "top": 0, "bottom": 0}}
        p["padding"] = {"enabled": True, "side": {"left": 6, "right": 6, "top": 0, "bottom": 0}}
        b = p["border"]
        b.update({"enabled": True, "customSides": False, "width": 1})
        b["color"] = system_color(b["color"], "textColor", "Window", 0.12)
        sh = p["shadow"]["background"]
        sh["enabled"] = True
        sh["color"].update({"enabled": True, "sourceType": 0, "custom": "#000000", "alpha": 0.45})
        if "size" in sh:
            sh["size"] = 14

    # Own background instead of Breeze's panel background; popups float
    g["nativePanel"] = {"background": {"enabled": False, "opacity": 0, "shadow": False},
                        "floatingDialogs": True, "floatingDialogsAllowOverride": True}
    for v in g["stockPanelSettings"].values():
        if isinstance(v, dict):
            v["enabled"] = False
    return g


if __name__ == "__main__":
    print(json.dumps(style(sys.argv[1] if len(sys.argv) > 1 else "dock"), separators=(",", ":")))
