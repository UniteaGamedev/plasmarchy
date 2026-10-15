"""Shared paths and theme helpers for Plasmarchy.

Themes live in two places:
  - built-in:  ~/.local/share/plasmarchy/themes/<slug>   (replaced on updates)
  - custom:    ~/.config/plasmarchy/themes/<slug>        (owned by the user, override built-ins of the same name)
Each theme contains colors.toml (Omarchy format), optionally kde.conf, preview.png and backgrounds/.
"""
import os
import tomllib

HOME = os.path.expanduser("~")
XDG_DATA = os.environ.get("XDG_DATA_HOME", os.path.join(HOME, ".local/share"))
XDG_CONFIG = os.environ.get("XDG_CONFIG_HOME", os.path.join(HOME, ".config"))
XDG_CACHE = os.environ.get("XDG_CACHE_HOME", os.path.join(HOME, ".cache"))

BASE = os.path.join(XDG_DATA, "plasmarchy")
BUILTIN_THEMES = os.path.join(BASE, "themes")
EXTRA_THEMES = os.path.join(BASE, "themes-extra")      # installed from the theme catalog
HIDDEN_THEMES = os.path.join(XDG_CONFIG, "plasmarchy", "hidden-themes")   # removed built-in themes, one per line


def hidden_themes():
    try:
        return {l.strip() for l in open(HIDDEN_THEMES) if l.strip()}
    except OSError:
        return set()


def set_hidden(slug, hidden):
    h = hidden_themes()
    h = h | {slug} if hidden else h - {slug}
    os.makedirs(os.path.dirname(HIDDEN_THEMES), exist_ok=True)
    open(HIDDEN_THEMES, "w").write("".join(f"{x}\n" for x in sorted(h)))
USER_THEMES = os.path.join(XDG_CONFIG, "plasmarchy", "themes")
CACHE = os.path.join(XDG_CACHE, "plasmarchy")

PALETTE_KEYS = [
    "accent", "selection", "muted",
    "background", "dark_background", "darker_background", "lighter_background",
    "foreground", "dark_foreground", "light_foreground", "bright_foreground",
    "red", "yellow", "orange", "green", "cyan", "blue", "magenta", "brown",
    "bright_red", "bright_yellow", "bright_green", "bright_cyan", "bright_blue", "bright_magenta",
]
FOLDER_COLORS = ["adwaita", "black", "blue", "bluegrey", "breeze", "brown", "carmine", "cyan", "darkcyan",
                 "deeporange", "green", "grey", "indigo", "magenta", "nordic", "orange", "palebrown",
                 "paleorange", "pink", "red", "teal", "violet", "white", "yaru", "yellow"]
IMAGE_EXT = (".webp", ".png", ".jpg", ".jpeg")


def themes():
    """{slug: directory} - custom themes override catalog and built-in themes of the same name."""
    found = {}
    hidden = hidden_themes()
    for root in (BUILTIN_THEMES, EXTRA_THEMES, USER_THEMES):
        if os.path.isdir(root):
            for slug in os.listdir(root):
                if root == BUILTIN_THEMES and slug in hidden:   # removed by the user (back via "More themes")
                    continue
                if os.path.isfile(os.path.join(root, slug, "colors.toml")):
                    found[slug] = os.path.join(root, slug)
    return dict(sorted(found.items()))


def theme_dir(slug):
    path = themes().get(slug)
    if not path:
        from i18n import tr
        raise SystemExit("plasmarchy: " + tr("Theme '{0}' does not exist", slug))
    return path


def is_user_theme(slug):
    return os.path.isfile(os.path.join(USER_THEMES, slug, "colors.toml"))


def is_builtin_theme(slug):
    """Shipped with Plasmarchy or installed from the catalog - read-only, can be duplicated."""
    return any(os.path.isfile(os.path.join(root, slug, "colors.toml")) for root in (BUILTIN_THEMES, EXTRA_THEMES))


def is_extra_theme(slug):
    return os.path.isfile(os.path.join(EXTRA_THEMES, slug, "colors.toml"))


def load_colors(slug):
    with open(os.path.join(theme_dir(slug), "colors.toml"), "rb") as f:
        c = tomllib.load(f)
    c.setdefault("mode", "dark")
    c.setdefault("orange", c.get("yellow", "#d08770"))
    c.setdefault("brown", c["orange"])
    return c


def load_kde_conf(slug):
    conf = {}
    path = os.path.join(theme_dir(slug), "kde.conf")
    if os.path.isfile(path):
        for line in open(path):
            if "=" in line and not line.lstrip().startswith("#"):
                k, v = line.strip().split("=", 1)
                conf[k.strip()] = v.strip().strip('"')
    return conf


def display_name(slug):
    conf = load_kde_conf(slug) if slug in themes() else {}
    if conf.get("NAME"):
        return conf["NAME"]
    special = {"rose-pine": "Rosé Pine"}
    return special.get(slug, " ".join(w.capitalize() for w in slug.split("-")))


def scheme_id(slug):
    return "Plasmarchy" + "".join(w.capitalize() for w in slug.split("-"))


def backgrounds(slug):
    """Wallpapers: files in backgrounds/ plus paths listed in backgrounds.list (user images without copying)."""
    d = theme_dir(slug)
    folder = os.path.join(d, "backgrounds")
    files = []
    if os.path.isdir(folder):
        files = [os.path.join(folder, f) for f in sorted(os.listdir(folder)) if f.lower().endswith(IMAGE_EXT)]
    listing = os.path.join(d, "backgrounds.list")
    if os.path.isfile(listing):
        files += [p.strip() for p in open(listing) if p.strip() and os.path.isfile(os.path.expanduser(p.strip()))]
    return [os.path.expanduser(f) for f in files]


def current_theme():
    state = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.join(HOME, ".local/state")), "plasmarchy", "current")
    try:
        return open(state).readline().strip() or "osaka-jade"
    except OSError:
        return "osaka-jade"


def current_colors():
    """Palette of the active theme (falls back to neutral colors)."""
    try:
        return load_colors(current_theme())
    except Exception:
        return {"background": "#111111", "foreground": "#dddddd", "accent": "#88aaff", "muted": "#666666"}
