#!/usr/bin/python3 -I
"""Branding: the logo shown by the screensaver and the animated wallpapers (like Omarchy's branding folder).

Files in ~/.config/plasmarchy/branding/:
  screensaver.txt   ASCII art the screensaver animates - edit it freely, it is used as is
  logo.png          white logo mask (transparent background) for the animated wallpapers
  source.*          the image or text the files above were generated from

  branding.py text "<text>"      render a text in a bold font
  branding.py image <file>       use an image (SVG, PNG, JPG ...); transparent or plain backgrounds both work
  branding.py ensure             create the default (distribution name) if nothing exists yet
  branding.py show               print the current ASCII logo
  branding.py info               JSON: paths and source
"""
import json
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from i18n import tr  # noqa: E402

HOME = os.path.expanduser("~")
DIR = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.join(HOME, ".config")), "plasmarchy", "branding")
TXT = os.path.join(DIR, "screensaver.txt")
PNG = os.path.join(DIR, "logo.png")
MAX_COLS, MAX_ROWS = 90, 24     # ASCII logo size in terminal cells (each cell = 1x2 "pixels")


def magick(*args, **kw):
    args = list(args)
    if args and args[-1] == "pgm:-":
        args[-1:] = ["-depth", "8", "pgm:-"]   # 8-bit samples (read_pgm expects one byte per pixel)
    return subprocess.run(["magick", *args], check=True, capture_output=True, **kw).stdout


def read_pgm(data):
    """Parse a binary PGM (P5) -> (width, height, bytes)."""
    parts, pos = [], 0
    while len(parts) < 4:
        while data[pos:pos + 1].isspace():
            pos += 1
        if data[pos:pos + 1] == b"#":
            pos = data.index(b"\n", pos)
            continue
        end = pos
        while not data[end:end + 1].isspace():
            end += 1
        parts.append(data[pos:end])
        pos = end
    w, h = int(parts[1]), int(parts[2])
    return w, h, data[pos + 1:pos + 1 + w * h]


def mask_from(src):
    """Grayscale mask (white = logo) of an image file, as a PGM byte string at high resolution."""
    opaque = magick("identify", "-format", "%[opaque]", src + "[0]").decode().strip().lower() == "true"
    if not opaque:   # transparent background: the alpha channel is the logo
        return magick("-background", "none", "-density", "300", src + "[0]", "-resize", "1024x1024>",
                      "-alpha", "extract", "pgm:-")
    gray = magick("-density", "300", src + "[0]", "-resize", "1024x1024>", "-colorspace", "gray", "pgm:-")
    w, h, px = read_pgm(gray)
    corners = [px[0], px[w - 1], px[(h - 1) * w], px[h * w - 1]]
    if sum(corners) / 4 > 127:   # dark logo on a light background -> invert
        return magick("pgm:-", "-negate", "pgm:-", input=gray)
    return gray


def to_ascii(mask_pgm):
    """Mask -> block characters. Each cell holds two vertical pixels: █ ▀ ▄ or space."""
    trimmed = magick("pgm:-", "-threshold", "50%", "-trim", "+repage", "pgm:-", input=mask_pgm)
    w, h, _ = read_pgm(trimmed)
    cols = min(MAX_COLS, max(8, round(w * (MAX_ROWS * 2) / h)))   # square pixels: cell = 1 wide, 2 high
    rows2 = max(2, round(h * cols / w))
    if rows2 > MAX_ROWS * 2:
        rows2 = MAX_ROWS * 2
        cols = max(8, round(w * rows2 / h))
    small = magick("pgm:-", "-resize", f"{cols}x{rows2}!", "-threshold", "50%", "pgm:-", input=trimmed)
    w, h, px = read_pgm(small)
    on = lambda x, y: y < h and px[y * w + x] > 127  # noqa: E731
    lines = []
    for y in range(0, h, 2):
        line = "".join("█" if on(x, y) and on(x, y + 1) else "▀" if on(x, y) else "▄" if on(x, y + 1) else " "
                       for x in range(w))
        lines.append(line.rstrip())
    return "\n".join(lines).strip("\n") + "\n"


def save(mask_pgm):
    os.makedirs(DIR, exist_ok=True)
    open(TXT, "w", encoding="utf-8").write(to_ascii(mask_pgm))
    # Wallpaper logo: white with the mask as transparency, trimmed
    magick("pgm:-", "-trim", "+repage", "(", "+clone", "-fill", "white", "-colorize", "100", ")", "+swap",
           "-alpha", "off", "-compose", "CopyOpacity", "-composite", PNG, input=mask_pgm)


def font():
    out = subprocess.run(["fc-match", "-f", "%{file}", "JetBrainsMono Nerd Font:style=ExtraBold"],
                         capture_output=True, text=True).stdout
    return out or "DejaVu-Sans-Bold"


def from_text(text):
    mask = magick("-background", "black", "-fill", "white", "-font", font(), "-pointsize", "240",
                  "label:" + text, "pgm:-")
    save(mask)
    for f in os.listdir(DIR):
        if f.startswith("source."):
            os.remove(os.path.join(DIR, f))
    open(os.path.join(DIR, "source.txt"), "w", encoding="utf-8").write(text + "\n")


def from_image(path):
    if not os.path.isfile(path):
        raise SystemExit(tr("File not found: {0}", path))
    save(mask_from(path))
    for f in os.listdir(DIR):
        if f.startswith("source."):
            os.remove(os.path.join(DIR, f))
    shutil.copy(path, os.path.join(DIR, "source" + os.path.splitext(path)[1].lower()))


def default_text():
    """Old screensaver TEXT setting, otherwise the distribution name (e.g. "CachyOS")."""
    conf = os.path.join(os.path.dirname(DIR), "screensaver.conf")
    if os.path.isfile(conf):
        for line in open(conf):
            if line.startswith("TEXT="):
                return line.split("=", 1)[1].strip().strip('"') or "Plasmarchy"
    try:
        for line in open("/etc/os-release"):
            if line.startswith("NAME="):
                return line.split("=", 1)[1].strip().strip('"').split()[0]
    except OSError:
        pass
    return "Plasmarchy"


def ensure():
    if not os.path.isfile(TXT) or not os.path.isfile(PNG):
        src = next((os.path.join(DIR, f) for f in sorted(os.listdir(DIR)) if f.startswith("source.")
                    and not f.endswith(".txt")), None) if os.path.isdir(DIR) else None
        if src:
            from_image(src)
        else:
            from_text(default_text())


def info():
    src = ""
    if os.path.isfile(os.path.join(DIR, "source.txt")):
        src = open(os.path.join(DIR, "source.txt"), encoding="utf-8").read().strip()
    elif os.path.isdir(DIR):
        src = next((os.path.join(DIR, f) for f in os.listdir(DIR) if f.startswith("source.")), "")
    return {"dir": DIR, "ascii": TXT, "logo": PNG, "source": src}


def main():
    a = sys.argv[1:]
    if a[:1] == ["text"] and len(a) >= 2:
        from_text(" ".join(a[1:]))
    elif a[:1] == ["image"] and len(a) == 2:
        from_image(os.path.abspath(a[1]))
    elif a[:1] == ["ensure"]:
        ensure()
        return
    elif a[:1] == ["info"]:
        print(json.dumps(info(), ensure_ascii=False))
        return
    elif a[:1] != ["show"]:
        raise SystemExit(__doc__)
    ensure()
    print(open(TXT, encoding="utf-8").read(), end="")


if __name__ == "__main__":
    main()
