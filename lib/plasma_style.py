#!/usr/bin/python3 -I
"""Generate the Plasma style "Plasmarchy": Breeze with Omarchy-like popups.

Popups (Wi-Fi, Bluetooth, volume, calendar, notifications ...) get a 2 px border in the theme's accent color,
roomier padding and a calmer, more solid background. Everything else falls back to Breeze ("default").
Colors come from the color scheme -> they follow every theme switch.
Target: ~/.local/share/plasma/desktoptheme/plasmarchy
"""
import gzip
import json
import os
import re
import shutil

SRC = "/usr/share/plasma/desktoptheme/default"
DEST = os.path.join(os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share")),
                    "plasma", "desktoptheme", "plasmarchy")
VARIANTS = ["", "translucent/", "solid/"]     # same geometry; "opaque" (no compositing) stays Breeze
BORDER = 'class="ColorScheme-Highlight" style="fill:currentColor"'
PADDING = 12   # popup padding (Breeze: 6) - otherwise content sticks to the border

# Border per frame piece (local coordinates, edges 32 px long, corners 6x6 with radius 6)
ADD = {
    "top": f'<rect x="0" y="0" width="32" height="2" {BORDER}/>',
    "bottom": f'<rect x="0" y="4" width="32" height="2" {BORDER}/>',
    "left": f'<rect x="0" y="0" width="2" height="32" {BORDER}/>',
    "right": f'<rect x="4" y="0" width="2" height="32" {BORDER}/>',
    # Corners as filled rings (radius 6 outside, 4 inside) - a stroke looked thinner due to anti-aliasing
    "topleft": f'<path d="M 0,6 C 0,2.69 2.69,0 6,0 L 6,2 C 3.79,2 2,3.79 2,6 Z" {BORDER}/>',
    "topright": f'<path d="M 0,0 C 3.31,0 6,2.69 6,6 L 4,6 C 4,3.79 2.21,2 0,2 Z" {BORDER}/>',
    "bottomleft": f'<path d="M 0,0 C 0,3.31 2.69,6 6,6 L 6,4 C 3.79,4 2,2.21 2,0 Z" {BORDER}/>',
    "bottomright": f'<path d="M 6,0 C 6,3.31 3.31,6 0,6 L 0,4 C 2.21,4 4,2.21 4,0 Z" {BORDER}/>',
}
# Plasma uses the size of these elements as content margins instead of the border width
MARGINS = "".join(
    f'<rect id="hint-{side}-margin" x="{-200 - i * 40}" y="-200" width="{w}" height="{h}" style="fill:#000;opacity:0"/>'
    for i, (side, w, h) in enumerate([("top", 1, PADDING), ("bottom", 1, PADDING),
                                      ("left", PADDING, 1), ("right", PADDING, 1)]))


def patch(svg):
    # Declare the accent as a color class (Plasma replaces the values with the color scheme at runtime)
    svg = svg.replace("</style>", ".ColorScheme-Highlight { color:#3daee9; stop-color:#3daee9; }\n</style>", 1)
    for gid, extra in ADD.items():
        m = re.search(r'(<g\b[^>]*\bid="' + gid + r'"[^>]*>)(.*?)(</g>)', svg, re.S)
        if not m:
            raise SystemExit(f"frame piece '{gid}' not found - Breeze has changed")
        body = m.group(2).replace("opacity:0.85", "opacity:0.96")   # calmer, more solid background
        svg = svg[:m.start()] + m.group(1) + body + extra + m.group(3) + svg[m.end():]
    svg = re.sub(r'<rect[^>]*id="hint-(top|bottom|left|right)-margin"[^>]*/>', "", svg)
    return svg.replace("</svg>", MARGINS + "\n</svg>")


def main():
    if not os.path.isdir(SRC):
        raise SystemExit("Breeze Plasma style not found")
    shutil.rmtree(DEST, ignore_errors=True)
    os.makedirs(DEST)
    meta = json.load(open(os.path.join(SRC, "metadata.json")))
    meta["KPlugin"].update({"Id": "plasmarchy", "Name": "Plasmarchy",
                            "Description": "Breeze with Omarchy-like popups (Plasmarchy)"})
    json.dump(meta, open(os.path.join(DEST, "metadata.json"), "w"), indent=4)
    if os.path.isfile(os.path.join(SRC, "plasmarc")):
        shutil.copy(os.path.join(SRC, "plasmarc"), DEST)
    for v in VARIANTS:
        src = os.path.join(SRC, v, "dialogs", "background.svgz")
        if not os.path.isfile(src):
            continue
        out = os.path.join(DEST, v, "dialogs", "background.svgz")
        os.makedirs(os.path.dirname(out), exist_ok=True)
        with gzip.open(src, "rt") as f:
            svg = patch(f.read())
        with gzip.open(out, "wt") as f:
            f.write(svg)
    # Plasma caches rendered style graphics - otherwise old borders stay visible
    cache = os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache"))
    for f in os.listdir(cache) if os.path.isdir(cache) else []:
        if f.startswith(("plasma_theme_plasmarchy", "plasma-svgelements-plasmarchy")):
            try:
                os.remove(os.path.join(cache, f))
            except OSError:
                pass
    print(DEST)


if __name__ == "__main__":
    main()
