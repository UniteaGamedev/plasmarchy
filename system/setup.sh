#!/bin/bash
# System-wide part of Plasmarchy (run as root by install.sh / uninstall.sh):
# the login screen helper, its polkit rule and the animated wallpaper for the login screen.
#
#   setup.sh install <repository>
#   setup.sh remove
set -euo pipefail

HELPER=/usr/local/lib/plasmarchy/login-screen
POLICY=/usr/share/polkit-1/actions/org.plasmarchy.login-screen.policy
WALLPAPER=/usr/local/share/plasma/wallpapers/org.plasmarchy.animated

[ "$(id -u)" -eq 0 ] || { echo "setup.sh: must run as root" >&2; exit 1; }

case "${1:-}" in
    install)
        src="${2:?repository missing}"
        install -D -m 755 -o root -g root "$src/system/login-screen" "$HELPER"
        install -D -m 644 -o root -g root "$src/system/org.plasmarchy.login-screen.policy" "$POLICY"
        # Code the login screen runs: root-owned and only from the repository, never from user data
        rm -rf "$WALLPAPER"
        mkdir -p "$(dirname "$WALLPAPER")"
        cp -r "$src/plasmoids/org.plasmarchy.animated" "$WALLPAPER"
        rm -rf "$WALLPAPER/shaders-src" "$WALLPAPER/contents/locale"
        chown -R root:root "$WALLPAPER"
        chmod -R u=rwX,go=rX "$WALLPAPER"
        ;;
    remove)
        [ -x "$HELPER" ] && "$HELPER" reset || true
        rm -rf "$HELPER" "$(dirname "$HELPER")" "$POLICY" "$WALLPAPER" 2>/dev/null || true
        ;;
    *)
        sed -n 2,7p "$0"; exit 1 ;;
esac
