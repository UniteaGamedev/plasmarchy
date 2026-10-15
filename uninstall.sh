#!/bin/bash
# Remove Plasmarchy and restore the state from before the installation.
#   ./uninstall.sh            reset everything (your own themes in ~/.config/plasmarchy are kept)
#   ./uninstall.sh --purge    also delete your own themes and settings
# Installed packages (Papirus, Nerd Font, swayidle ...) stay installed.
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="${XDG_DATA_HOME:-$HOME/.local/share}/plasmarchy"
BIN="$HOME/.local/bin/plasmarchy"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/plasmarchy"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/plasmarchy"
PURGE=0; [ "${1:-}" = "--purge" ] && PURGE=1

t() {   # translated message (catalog from the repository - the installed copy gets removed)
    if [ -f "$SRC/lib/i18n.py" ]; then python3 -I "$SRC/lib/i18n.py" tr "$@"; else printf '%s\n' "$1"; fi
}
step() { printf '\n\033[1;32m==>\033[0m %s\n' "$*"; }

step "$(t "Stopping services")"
systemctl --user disable --now plasmarchy-idle.service >/dev/null 2>&1
systemctl --user disable --now plasmarchy-wake.service >/dev/null 2>&1
rm -f "$HOME/.config/systemd/user/plasmarchy-idle.service" "$HOME/.config/systemd/user/plasmarchy-wake.service"
systemctl --user daemon-reload

# Backed-up files first, then the look - otherwise the files would overwrite the restored look
if [ -d "$STATE_DIR/backup/initial" ]; then
    step "$(t "Restoring backed-up KDE settings (panels, effects, search, System Settings)")"
    for f in "$STATE_DIR"/backup/initial/*; do
        cp -a "$f" "$HOME/.config/"
    done
    if [ -f "$STATE_DIR/backup/initial.absent" ]; then
        while read -r f; do [ -n "$f" ] && rm -f "$HOME/.config/$f"; done < "$STATE_DIR/backup/initial.absent"
    fi
else
    step "$(t "No initial backup found - removing only the Plasmarchy entries")"
    kwriteconfig6 --file kdeglobals --group "KDE Control Module Restrictions" --key kcm_lookandfeel --delete
    for kcm in kcm_colors kcm_desktoptheme kcm_kwindecoration kcm_icons; do
        kwriteconfig6 --file kdeglobals --group "KDE Control Module Restrictions" --key "$kcm" --delete
    done
fi

step "$(t "Resetting the look (colors, icons, wallpaper, terminal)")"
[ -x "$BIN" ] && "$BIN" restore || true

step "$(t "Removing files")"
kpackagetool6 -t Plasma/Applet -r org.plasmarchy.aiusage >/dev/null 2>&1
kpackagetool6 -t Plasma/Applet -r org.plasmarchy.music >/dev/null 2>&1
kpackagetool6 -t Plasma/Wallpaper -r org.plasmarchy.animated >/dev/null 2>&1
rm -rf "$BASE" "$BIN" "${XDG_CACHE_HOME:-$HOME/.cache}/plasmarchy"
rm -f "$HOME"/.local/share/applications/plasmarchy-*.desktop
rm -f "$HOME"/.local/share/color-schemes/Plasmarchy*.colors "$HOME"/.local/share/konsole/Plasmarchy*
rm -rf "$HOME"/.local/share/icons/Papirus-Dark-* "$HOME"/.local/share/icons/Papirus-Light-*
rm -rf "$HOME"/.local/share/plasma/desktoptheme/plasmarchy
[ "$PURGE" = 1 ] && rm -rf "$CONF_DIR" "$STATE_DIR"
kwriteconfig6 --file kglobalshortcutsrc --group services --group plasmarchy-talk.desktop --key _launch --delete
kwriteconfig6 --file kglobalshortcutsrc --group services --group plasmarchy-menu.desktop --key _launch --delete
kbuildsycoca6 >/dev/null 2>&1

step "$(t "Reloading Plasma and KWin")"
qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1
systemctl --user restart plasma-plasmashell

echo
t "Plasmarchy has been removed."
[ "$PURGE" = 0 ] && t "Your own themes stay in {0} (delete them with --purge)." "$CONF_DIR"
t "Panel Colorizer (Plasma widget) and the packages stay installed."
