#!/bin/bash
# Install Plasmarchy: an Omarchy-like look for KDE Plasma 6 on CachyOS / Arch.
#
#   ./install.sh               set up everything (asks once for the sudo password for packages)
#   ./install.sh --no-layout   don't touch the panels/dock
#   ./install.sh --no-packages don't install packages (e.g. for updates)
#
# All affected KDE settings are backed up first; ./uninstall.sh restores them.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="${XDG_DATA_HOME:-$HOME/.local/share}/plasmarchy"
BIN="$HOME/.local/bin/plasmarchy"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/plasmarchy"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/plasmarchy"
COLORIZER_VERSION="v8.0.0"
COLORIZER_URL="https://github.com/luisbocanegra/plasma-panel-colorizer/releases/download/$COLORIZER_VERSION/plasmoid-panel-colorizer-$COLORIZER_VERSION.plasmoid"
DEFAULT_THEME="osaka-jade"

t() { python3 -I "$SRC/lib/i18n.py" tr "$@"; }   # translated message

LAYOUT=1; PACKAGES=1
for a in "$@"; do
    case "$a" in
        --no-layout)   LAYOUT=0 ;;
        --no-packages) PACKAGES=0 ;;
        *) t "Unknown option: {0}" "$a"; exit 1 ;;
    esac
done

step() { printf '\n\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  ! %s\033[0m\n' "$*"; }
k() { kwriteconfig6 --file "$@"; }

[ "$(id -u)" -ne 0 ] || { t "Please run without sudo. The installer asks for the password itself."; exit 1; }
command -v plasmashell >/dev/null && [ "$(plasmashell --version 2>/dev/null | grep -o '[0-9]*' | head -1)" -ge 6 ] \
    || { t "Plasmarchy needs KDE Plasma 6."; exit 1; }
[ "${XDG_SESSION_TYPE:-}" = wayland ] || warn "$(t "No Wayland session detected. The automatic screensaver needs Wayland.")"

# --- 1. Packages ---------------------------------------------------------------------------------
if [ "$PACKAGES" = 1 ]; then
    step "$(t "Installing packages")"
    pkgs=(python qt6-declarative qt6-imageformats kimageformats imagemagick papirus-icon-theme
          ttf-jetbrains-mono-nerd swayidle alacritty kdialog)
    # Rounded window corners are packaged on CachyOS only (on Arch: AUR kwin-effect-rounded-corners-git)
    pacman -Si kwin-effect-rounded-corners >/dev/null 2>&1 && pkgs+=(kwin-effect-rounded-corners) \
        || warn "$(t "kwin-effect-rounded-corners is not in the repositories, window corners stay square.")"
    sudo pacman -S --needed "${pkgs[@]}"
fi

# --- 2. Backup (first time only) -----------------------------------------------------------------
if [ ! -d "$STATE_DIR/backup/initial" ]; then
    step "$(t "Backing up current KDE settings")"
    mkdir -p "$STATE_DIR/backup/initial"
    for f in kdeglobals kwinrc krunnerrc kscreenlockerrc konsolerc plasmarc plasmashellrc \
             plasma-org.kde.plasma.desktop-appletsrc; do
        if [ -f "$HOME/.config/$f" ]; then cp -a "$HOME/.config/$f" "$STATE_DIR/backup/initial/"
        else echo "$f" >> "$STATE_DIR/backup/initial.absent"; fi   # didn't exist before -> delete on uninstall
    done
fi

# --- 3. Files -----------------------------------------------------------------------------------
step "$(t "Copying Plasmarchy files")"
mkdir -p "$BASE" "$HOME/.local/bin" "$CONF_DIR/themes" "$HOME/.local/share/applications" "$HOME/.config/systemd/user"
rm -rf "$BASE/lib" "$BASE/themes" "$BASE/hooks.d"
cp -a "$SRC/lib" "$SRC/themes" "$SRC/hooks.d" "$BASE/"
cp -a "$SRC/plasmoids" "$BASE/"
install -m 755 "$SRC/bin/plasmarchy" "$BIN"
for f in "$SRC"/applications/*.desktop; do
    sed "s|@BIN@|$BIN|g" "$f" > "$HOME/.local/share/applications/$(basename "$f")"
done
[ -f "$CONF_DIR/screensaver.conf" ] || cp "$SRC/config/screensaver.conf" "$CONF_DIR/"
[ -f "$CONF_DIR/assistant.conf" ] || cp "$SRC/config/assistant.conf" "$CONF_DIR/"
cp "$SRC/systemd/plasmarchy-idle.service" "$HOME/.config/systemd/user/"
cp "$SRC/systemd/plasmarchy-wake.service" "$HOME/.config/systemd/user/"
# "Plasmarchy" page in System Settings (Appearance) - must be executable to be trusted
mkdir -p "$HOME/.local/share/plasma/systemsettings/externalmodules"
sed "s|@BIN@|$BIN|g" "$SRC/systemsettings/plasmarchy.desktop" > "$HOME/.local/share/plasma/systemsettings/externalmodules/plasmarchy.desktop"
chmod +x "$HOME/.local/share/plasma/systemsettings/externalmodules/plasmarchy.desktop"
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
# Conversation hotkey: keep the one chosen in the settings (updates must not reset it)
hotkey="$(sed -n 's/^HOTKEY=//p' "$CONF_DIR/assistant.conf" 2>/dev/null | tr -d '"' | tail -1)"
kwriteconfig6 --file kglobalshortcutsrc --group services --group plasmarchy-talk.desktop --key _launch "${hotkey:-Meta+Shift+Space}"
systemctl --user restart plasma-kglobalaccel.service >/dev/null 2>&1 || true
kbuildsycoca6 >/dev/null 2>&1 || true

# --- 4. Plasma widgets ---------------------------------------------------------------------------
step "$(t "Installing Plasma widgets (Panel Colorizer {0}, AI assistant, music player, animated wallpaper)" "$COLORIZER_VERSION")"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
if curl -fsSL -o "$tmp/colorizer.plasmoid" "$COLORIZER_URL"; then
    kpackagetool6 -t Plasma/Applet -u "$tmp/colorizer.plasmoid" >/dev/null 2>&1 \
        || kpackagetool6 -t Plasma/Applet -i "$tmp/colorizer.plasmoid" >/dev/null
else
    warn "$(t "Couldn't download Panel Colorizer. The top bar and dock will be styled without rounding and colors.")"
fi
# Our widgets and the animated wallpaper; translations are compiled from the JSON catalogs into each package
for pkg in "$BASE"/plasmoids/*/; do
    id="$(basename "$pkg")"
    type=Plasma/Applet; domain="plasma_applet_$id"
    [ "$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get("KPackageStructure",""))' "$pkg/metadata.json")" = Plasma/Wallpaper ] \
        && { type=Plasma/Wallpaper; domain="plasma_wallpaper_$id"; }
    for cat in "$BASE"/lib/locale/*.json; do
        lang=$(basename "$cat" .json)
        python3 -I "$BASE/lib/i18n.py" build-mo "$lang" "$pkg/contents/locale/$lang/LC_MESSAGES/$domain.mo"
        # also in the standard location - Plasma doesn't look inside wallpaper packages
        mkdir -p "${XDG_DATA_HOME:-$HOME/.local/share}/locale/$lang/LC_MESSAGES"
        cp "$pkg/contents/locale/$lang/LC_MESSAGES/$domain.mo" "${XDG_DATA_HOME:-$HOME/.local/share}/locale/$lang/LC_MESSAGES/"
    done
    kpackagetool6 -t "$type" -u "$pkg" >/dev/null 2>&1 || kpackagetool6 -t "$type" -i "$pkg" >/dev/null
done

# --- 5. Prepare themes -------------------------------------------------------------------------
step "$(t "Generating color schemes, folder colors and previews")"
python3 -I "$BASE/lib/gen.py" >/dev/null
python3 -I "$BASE/lib/plasma_style.py" >/dev/null     # Plasma style with Omarchy-like popups
python3 -I "$BASE/lib/folder_overlays.py" >/dev/null
python3 -I "$BASE/lib/manifest.py" "${XDG_RUNTIME_DIR:-/tmp}/plasmarchy-themes.json" >/dev/null
fc-cache -f >/dev/null 2>&1 || true

# --- 6. KDE settings ----------------------------------------------------------------------------
step "$(t "Setting up animations, effects and the centered search")"
k kdeglobals --group KDE --key AnimationDurationFactor 0.8
k kwinrc --group Plugins --key scaleEnabled true
k kwinrc --group Plugins --key fadeEnabled false
k kwinrc --group Plugins --key magiclampEnabled true
k kwinrc --group Plugins --key squashEnabled false
k kwinrc --group Plugins --key blurEnabled true
k kwinrc --group Plugins --key wobblywindowsEnabled false
k kwinrc --group Effect-blur --key BlurStrength 10
k kwinrc --group Effect-blur --key NoiseStrength 0
k kwinrc --group Desktops --key Number 1
k kwinrc --group Desktops --key Rows 1
# The Windows key opens the Plasmarchy menu (Omarchy-style); KRunner stays reachable from its search
k krunnerrc --group General --key FreeFloating true
kwriteconfig6 --file kglobalshortcutsrc --group services --group plasmarchy-menu.desktop --key _launch "Meta+Alt+Space"
# Plasma's default Windows-key action opens the launcher of the panel - that's our menu button
k kwinrc --group ModifierOnlyShortcuts --key Meta --delete
if pacman -Q kwin-effect-rounded-corners >/dev/null 2>&1; then
    # only the effect plugin, not its settings page (effects/configs/...)
    so="$(pacman -Ql kwin-effect-rounded-corners | awk '/\/effects\/plugins\/.*\.so$/{print $2}' | head -1)"
    id="$(basename "${so:-kwin4_effect_shapecorners.so}" .so)"
    k kwinrc --group Plugins --key "${id}Enabled" true
    k kwinrc --group Round-Corners --key Size 12
    qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect "$id" >/dev/null 2>&1 || true
fi
qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
for e in magiclamp blur scale; do qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect "$e" >/dev/null 2>&1 || true; done
qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect squash >/dev/null 2>&1 || true
# Hot corner: top left opens the overview of all windows (also KDE's default - set explicitly)
k kwinrc --group Effect-overview --key BorderActivate 9
kquitapp6 krunner >/dev/null 2>&1 || true

step "$(t "Tidying up System Settings (pages Plasmarchy controls are hidden)")"
# kcm_landingpage: KDE's "Quick Settings" offer KDE's global themes - Plasmarchy's own page replaces them
for kcm in kcm_lookandfeel kcm_colors kcm_desktoptheme kcm_kwindecoration kcm_icons kcm_landingpage; do
    k kdeglobals --group "KDE Control Module Restrictions" --key "$kcm" false
done

# --- 7. Theme, panels, screensaver --------------------------------------------------------------
step "$(t "Applying theme")"
current="$(head -1 "$STATE_DIR/current" 2>/dev/null || true)"
# The active theme moved to the catalog (or was installed from it): install it from this checkout
if [ -n "$current" ] && [ ! -d "$BASE/themes/$current" ] && [ -d "$SRC/extra-themes/$current" ] \
        && [ ! -d "${XDG_CONFIG_HOME:-$HOME/.config}/plasmarchy/themes/$current" ]; then
    python3 -I "$BASE/lib/themestore.py" install "$current" --from "$SRC/extra-themes" >/dev/null
fi
"$BIN" theme "${current:-$DEFAULT_THEME}"

if [ "$LAYOUT" = 1 ]; then
    step "$(t "Setting up the top bar and dock")"
    "$BIN" layout
else
    python3 -I "$BASE/lib/layout.py" migrate   # update an existing top bar (menu button, AI in the tray)
fi

step "$(t "Setting up the screensaver")"
"$BIN" screensaver setup >/dev/null || warn "$(t "Screensaver setup failed. Retry with: {0}" "plasmarchy screensaver setup")"
step "$(t "Enabling the idle screensaver")"
systemctl --user daemon-reload
systemctl --user enable plasmarchy-idle.service >/dev/null 2>&1
# restart instead of --now: an already running service may still be waiting without swayidle
systemctl --user restart plasmarchy-idle.service >/dev/null 2>&1 || warn "$(t "Idle service not started (swayidle?)")"

printf '\n\033[1;32m%s\033[0m\n' "$(t "Plasmarchy is set up.")"
t "$(cat <<'EOF'
  Menu:              Windows key (search, apps, style, toggles, setup, system)
  Switch theme:      menu "Style"  or  plasmarchy
  Theme Studio:      menu "Style"  or  plasmarchy studio
  Logo:              menu "Style"  or  plasmarchy branding
  AI assistant:      robot icon top right  or  Meta+A
  Talk to your PC:   {0} (press again to send, say "stop" to end)
  Music player:      top left, with YouTube Music built in (plasmarchy music setup)
  Voice (optional, ~650 MB, local):     plasmarchy voice setup
  Local AI (optional, fallback AI):     plasmarchy llm setup
  Undo:              {1}

  Rounded window corners become active after logging out and back in.
EOF
)" "${hotkey:-Meta+Shift+Space}" "$SRC/uninstall.sh"
