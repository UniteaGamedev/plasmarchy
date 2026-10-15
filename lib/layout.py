#!/usr/bin/python3 -I
"""Set up the Plasmarchy panels: slim top bar + rounded dock.

- existing panels are replaced (the Plasma config is backed up to ~/.local/state/plasmarchy/backup first)
- apps pinned to the dock are kept; without a dock, common apps are pinned
- Plasma is restarted afterwards (Panel Colorizer only reads its settings at startup)
"""
import json
import os
import shutil
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from plasmarchy_common import HOME, XDG_CONFIG  # noqa: E402
from panel_style import style  # noqa: E402
from i18n import tr  # noqa: E402

STATE_BACKUP = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.join(HOME, ".local/state")),
                            "plasmarchy", "backup")
APPLETSRC = os.path.join(XDG_CONFIG, "plasma-org.kde.plasma.desktop-appletsrc")

# Only Wi-Fi, Bluetooth, volume and battery stay visible in the tray (plus items that show up when needed)
HIDDEN_TRAY = ["org.kde.kdeconnect", "org.kde.plasma.clipboard", "org.kde.kscreen", "org.kde.plasma.brightness",
               "org.kde.plasma.keyboardindicator", "org.kde.plasma.keyboardlayout",
               "org.kde.plasma.manage-inputmethod", "org.kde.plasma.weather", "org.kde.plasma.devicenotifier",
               "Cachy-Update", "unityhub_status_icon_1",
               "kded6"]   # KDE hints such as "Get Plasma Browser Integration"
MASKED_TRAY = ["org.plasmarchy.aiusage", "org.kde.plasma.bluetooth", "org.kde.plasma.battery", "org.kde.plasma.volume",
               "org.kde.plasma.networkmanagement", "org.kde.plasma.systemtray.expand"]
DEFAULT_APPS = [["firefox.desktop", "chromium.desktop", "brave-browser.desktop", "zen.desktop"],
                ["org.kde.dolphin.desktop"], ["org.kde.konsole.desktop"],
                ["plasmarchy-theme.desktop"], ["systemsettings.desktop"]]


def evaluate(script):
    out = subprocess.run(["qdbus6", "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript",
                          script], capture_output=True, text=True)
    if out.returncode != 0:
        raise SystemExit(tr("Plasma script failed: {0}", out.stderr.strip()))
    return out.stdout.strip()


def app_installed(desktop_id):
    dirs = [os.path.join(HOME, ".local/share/applications"), "/usr/share/applications",
            "/var/lib/flatpak/exports/share/applications"]
    return any(os.path.isfile(os.path.join(d, desktop_id)) for d in dirs)


def existing_launchers():
    raw = evaluate('''
        var l = [];
        panels().forEach(p => p.widgets().forEach(w => {
            if (w.type == "org.kde.plasma.icontasks" || w.type == "org.kde.plasma.taskmanager") {
                w.currentConfigGroup = ["General"];
                var v = w.readConfig("launchers"); if (v) l = l.concat(String(v).split(","));
            }}));
        print(JSON.stringify(l));''')
    return [x for x in json.loads(raw or "[]") if x]


def main():
    os.makedirs(STATE_BACKUP, exist_ok=True)
    if os.path.isfile(APPLETSRC):
        shutil.copy2(APPLETSRC, os.path.join(STATE_BACKUP, f"appletsrc-{time.strftime('%Y%m%d-%H%M%S')}"))

    launchers = existing_launchers()
    if not launchers:
        for choices in DEFAULT_APPS:
            hit = next((c for c in choices if app_installed(c)), None)
            if hit:
                launchers.append("applications:" + hit)

    # "Change theme" always belongs in the dock (before System Settings)
    theme_launcher = "applications:plasmarchy-theme.desktop"
    if theme_launcher not in launchers:
        pos = launchers.index("applications:systemsettings.desktop") if "applications:systemsettings.desktop" in launchers else len(launchers)
        launchers.insert(pos, theme_launcher)

    force = {"widgets": [{"name": n, "id": -1, "method": {"mask": True, "multiEffect": False}, "reload": False}
                         for n in MASKED_TRAY], "reloadInterval": 250}

    script = f'''
    panels().forEach(p => p.remove());

    // --- top bar ---
    var top = new Panel("org.kde.panel");
    top.location = "top"; top.height = 32; top.floating = false; top.hiding = "none";
    var menu = top.addWidget("org.plasmarchy.menu");   // opens the Plasmarchy menu; Plasma's Windows-key action targets it
    menu.globalShortcut = "Alt+F1";      // Plasma only hands the Windows key to launchers that have a shortcut
    {'top.addWidget("org.plasmarchy.music");  // music player, hides itself while nothing runs' if player_enabled() else ''}
    top.addWidget("org.kde.plasma.panelspacer");
    var clock = top.addWidget("org.kde.plasma.digitalclock");
    clock.currentConfigGroup = ["Appearance"];
    clock.writeConfig("autoFontAndSize", false);
    clock.writeConfig("fontFamily", "JetBrainsMono Nerd Font");
    clock.writeConfig("fontWeight", 400);
    clock.writeConfig("fontSize", 7);
    clock.writeConfig("showDate", true);
    clock.writeConfig("dateDisplayFormat", "BesideTime");
    clock.writeConfig("dateFormat", "custom");
    clock.writeConfig("customDateFormat", "dddd");
    top.addWidget("org.kde.plasma.panelspacer");
    // the AI assistant lives in the system tray (shares the popup with Wi-Fi, Bluetooth, volume)
    var tray = top.addWidget("org.kde.plasma.systemtray");
    tray.currentConfigGroup = ["General"];
    tray.writeConfig("hiddenItems", {json.dumps(HIDDEN_TRAY + (["org.kde.plasma.mediacontroller"] if player_enabled() else []))});
    tray.writeConfig("iconSpacing", 2);
    var ct = top.addWidget("luisbocanegra.panel.colorizer");
    ct.currentConfigGroup = ["General"];
    ct.writeConfig("isEnabled", true); ct.writeConfig("hideWidget", true);
    ct.writeConfig("globalSettings", {json.dumps(json.dumps(style("top"), separators=(",", ":")))});

    // --- dock ---
    var dock = new Panel("org.kde.panel");
    dock.location = "bottom"; dock.height = 56; dock.floating = true;
    dock.lengthMode = "fit"; dock.alignment = "center"; dock.hiding = "dodgewindows";
    var tasks = dock.addWidget("org.kde.plasma.icontasks");
    tasks.currentConfigGroup = ["General"];
    tasks.writeConfig("launchers", {json.dumps(",".join(launchers))});
    tasks.writeConfig("iconSpacing", 2);
    var cd = dock.addWidget("luisbocanegra.panel.colorizer");
    cd.currentConfigGroup = ["General"];
    cd.writeConfig("isEnabled", true); cd.writeConfig("hideWidget", true);
    cd.writeConfig("globalSettings", {json.dumps(json.dumps(style("dock"), separators=(",", ":")))});
    print("ok");
    '''
    print(evaluate(script))
    # Panel Colorizer only learns the tray items at startup and drops tint entries for unknown items
    # -> start once, then write the tint config, then restart again.
    restart_plasma()
    evaluate(f'''
        panels().forEach(p => {{
            if (p.location != "top") return;
            var force = {json.dumps(force)};
            p.widgets().filter(w => w.type == "luisbocanegra.panel.colorizer").forEach(c => {{
                c.currentConfigGroup = ["General"];
                c.writeConfig("forceForegroundColor", JSON.stringify(force));
            }});
        }});''')
    restart_plasma(before_start=tray_ai_shortcut)
    print(tr("Panels set up."))


TOPBAR_CONF = os.path.join(XDG_CONFIG, "plasmarchy", "topbar.conf")


def player_enabled():
    try:
        return "PLAYER=off" not in open(TOPBAR_CONF).read()
    except OSError:
        return True


def player(action):
    """Show/hide the music player in the top bar. Hiding removes it right away; showing puts it back next
    to the menu button (needs a Plasma restart to place it there)."""
    present = evaluate('''
        var r = "no";
        panels().forEach(p => { if (p.location == "top" && p.widgets().some(w => w.type == "org.plasmarchy.music")) r = "yes"; });
        print(r);''').strip() == "yes"
    on = (not present) if action == "toggle" else action == "on"
    os.makedirs(os.path.dirname(TOPBAR_CONF), exist_ok=True)
    open(TOPBAR_CONF, "w").write(f"# Top bar options (managed by plasmarchy)\nPLAYER={'on' if on else 'off'}\n")
    # KDE's own media controller in the tray would duplicate the player -> only show it while ours is off
    evaluate(f'''panels().forEach(p => p.widgets().forEach(w => {{
        if (w.type != "org.kde.plasma.systemtray") return;
        w.currentConfigGroup = ["General"];
        var hidden = w.readConfig("hiddenItems", []).filter(x => x != "org.kde.plasma.mediacontroller");
        if ({'true' if on else 'false'}) hidden.push("org.kde.plasma.mediacontroller");
        w.writeConfig("hiddenItems", hidden);
    }}));''')
    if not on:
        evaluate('''panels().forEach(p => p.widgets().forEach(w => { if (w.type == "org.plasmarchy.music") w.remove(); }));''')
    elif not present:
        order = evaluate('''
            var r = "";
            panels().forEach(p => {
                if (p.location != "top") return;
                var w = p.addWidget("org.plasmarchy.music");
                var ids = p.widgets().filter(x => x.id != w.id).map(x => x.id);
                var k = p.widgets().findIndex(x => x.type == "org.plasmarchy.menu" || x.type == "org.kde.plasma.kickoff");
                ids.splice(k + 1, 0, w.id);   // right after the menu button
                r = p.id + " " + ids.join(";");
            });
            print(r);''').strip()
        if order:
            panel, ids = order.split(" ", 1)
            subprocess.run(["systemctl", "--user", "stop", "plasma-plasmashell.service"], check=False)
            subprocess.run(["kwriteconfig6", "--file", APPLETSRC, "--group", "Containments", "--group", panel,
                            "--group", "General", "--key", "AppletOrder", ids], check=False)
            subprocess.run(["systemctl", "--user", "start", "plasma-plasmashell.service"], check=False)
    subprocess.run(["notify-send", "-a", "Plasmarchy", "-i", "media-playback-start", tr("Music player"),
                    tr("shown in the top bar") if on else tr("hidden")], check=False)
    print("on" if on else "off")


def launcher(style):
    """Switch the menu button: "plasmarchy" (centered Plasmarchy menu) or "kde" (classic KDE application menu).
    Either one gets the Windows key."""
    new, old = ("org.kde.plasma.kickoff", "org.plasmarchy.menu") if style == "kde" else ("org.plasmarchy.menu", "org.kde.plasma.kickoff")
    out = evaluate(f'''
        var r = "";
        panels().forEach(p => {{
            if (p.location != "top") return;
            var ws = p.widgets();
            if (ws.some(w => w.type == "{new}")) return;
            // visual order (AppletOrder); widgets() is in creation order
            p.currentConfigGroup = ["General"];
            var order = String(p.readConfig("AppletOrder", "")).split(";").filter(x => x).map(Number);
            if (!order.length) order = ws.map(w => w.id);
            var oldW = ws.filter(w => w.type == "{old}")[0];
            var pos = oldW ? Math.max(0, order.indexOf(oldW.id)) : 0;
            // release the old launcher's shortcut first - otherwise the new one can't get Alt+F1
            ws.filter(w => w.type == "{old}").forEach(w => {{ w.globalShortcut = ""; w.remove(); }});
            var w = p.addWidget("{new}");
            w.globalShortcut = "Alt+F1";   // Plasma hands the Windows key to the launcher with a shortcut
            if ("{new}" == "org.kde.plasma.kickoff") {{
                w.currentConfigGroup = ["General"]; w.writeConfig("icon", "view-app-grid-symbolic");
            }}
            var alive = p.widgets().map(x => x.id);
            var ids = order.filter(id => alive.indexOf(id) >= 0 && id != w.id);
            alive.forEach(id => {{ if (ids.indexOf(id) < 0 && id != w.id) ids.push(id); }});
            ids.splice(pos, 0, w.id);
            r = p.id + " " + ids.join(";");
        }});
        print(r);''').strip()
    if out:
        panel, ids = out.split(" ", 1)
        restart_plasma(before_start=lambda: subprocess.run(
            ["kwriteconfig6", "--file", APPLETSRC, "--group", "Containments", "--group", panel, "--group", "General",
             "--key", "AppletOrder", ids], check=False))
    print(style)


def migrate():
    """Bring an existing top bar up to date without rebuilding it: menu button instead of kickoff,
    AI assistant in the system tray, music player next to the menu button. Safe to run repeatedly."""
    out = evaluate('''
        var r = "";
        panels().forEach(p => {
            if (p.location != "top") return;
            var ws = p.widgets();
            if (!ws.some(w => w.type == "org.plasmarchy.menu")) {
                var m = p.addWidget("org.plasmarchy.menu");
                m.globalShortcut = "Alt+F1";   // Plasma only hands the Windows key to launchers with a shortcut
            }
            ws.filter(w => w.type == "org.kde.plasma.kickoff" || w.type == "org.plasmarchy.aiusage").forEach(w => w.remove());
            ws = p.widgets();
            var menu = ws.filter(w => w.type == "org.plasmarchy.menu")[0].id;
            var music = ws.filter(w => w.type == "org.plasmarchy.music").map(w => w.id);
            var rest = ws.filter(w => w.type != "org.plasmarchy.menu" && w.type != "org.plasmarchy.music").map(w => w.id);
            r = p.id + " " + [menu].concat(music, rest).join(";");
            // Panel Colorizer: tint the AI icon in the tray like the other tray icons
            ws.filter(w => w.type == "luisbocanegra.panel.colorizer").forEach(c => {
                c.currentConfigGroup = ["General"];
                try {
                    var f = JSON.parse(c.readConfig("forceForegroundColor", "{}"));
                    f.widgets = (f.widgets || []).filter(x => x.name != "org.kde.plasma.kickoff");
                    if (!f.widgets.some(x => x.name == "org.plasmarchy.aiusage"))
                        f.widgets.push({"name": "org.plasmarchy.aiusage", "id": -1, "method": {"mask": true, "multiEffect": false}, "reload": false});
                    c.writeConfig("forceForegroundColor", JSON.stringify(f));
                } catch (e) {}
            });
        });
        print(r);''').strip()
    # The Windows key uses Plasma's default action ("activate launcher menu") -> our menu button
    subprocess.run(["kwriteconfig6", "--file", "kwinrc", "--group", "ModifierOnlyShortcuts", "--key", "Meta",
                    "--delete"], check=False)
    subprocess.run(["qdbus6", "org.kde.KWin", "/KWin", "reconfigure"], capture_output=True)
    if not out:
        return

    def order():
        panel, ids = out.split(" ", 1)
        subprocess.run(["kwriteconfig6", "--file", APPLETSRC, "--group", "Containments", "--group", panel,
                        "--group", "General", "--key", "AppletOrder", ids], check=False)
    restart_plasma(before_start=order)        # the tray picks up the AI assistant on this start
    restart_plasma(before_start=tray_ai_shortcut)


AI_SHORTCUT = "Meta+A"   # like Omarchy's Super+A


def free_activity_keys():
    """Meta+A / Meta+Shift+A switch activities in KDE. With a single activity they do nothing, so they are
    released for the AI assistant. Users with several activities keep them (and the AI assistant has none)."""
    out = subprocess.run(["qdbus6", "org.kde.ActivityManager", "/ActivityManager/Activities",
                          "org.kde.ActivityManager.Activities.ListActivities"], capture_output=True, text=True).stdout
    if len(out.split()) > 1:
        return False
    for action, label in (("next activity", "Walk through activities"),
                          ("previous activity", "Walk through activities (Reverse)")):
        subprocess.run(["kwriteconfig6", "--file", "kglobalshortcutsrc", "--group", "plasmashell", "--key", action,
                        f"none,none,{label}"], check=False)
        subprocess.run(["busctl", "--user", "call", "org.kde.kglobalaccel", "/kglobalaccel", "org.kde.KGlobalAccel",
                        "setForeignShortcutKeys", "asa(ai)", "4", "plasmashell", action, "plasmashell", label, "0"],
                       capture_output=True)   # release right away, not only after the next login
    return True


def tray_ai_shortcut(seq=AI_SHORTCUT):
    """Keyboard shortcut for the AI assistant inside the system tray. Tray items can't be reached from Plasma
    scripts, so the shortcut is written into the config file while Plasma is stopped."""
    if not free_activity_keys():
        return
    import re
    try:
        text = open(APPLETSRC).read()
    except OSError:
        return
    m = re.search(r"^\[(Containments\]\[\d+\]\[Applets\]\[\d+\]\[Applets\]\[\d+)\]\n(?:[^\[\n][^\n]*\n)*?plugin=org\.plasmarchy\.aiusage$",
                  text, re.M)
    if m:
        groups = ["--group" if i % 2 == 0 else g for g in m.group(1).split("][") for i in (0, 1)]
        subprocess.run(["kwriteconfig6", "--file", APPLETSRC, *groups, "--group", "Shortcuts",
                        "--key", "global", seq], check=False)


def restart_plasma(before_start=None):
    # Several restarts in a row hit systemd's start limit and leave the desktop empty -> reset it first
    reset = ["systemctl", "--user", "reset-failed", "plasma-plasmashell"]
    if before_start:
        subprocess.run(["systemctl", "--user", "stop", "plasma-plasmashell"], check=False)
        before_start()
        subprocess.run(reset, capture_output=True)
        subprocess.run(["systemctl", "--user", "start", "plasma-plasmashell"], check=False)
    else:
        subprocess.run(reset, capture_output=True)
        subprocess.run(["systemctl", "--user", "restart", "plasma-plasmashell"], check=False)
    time.sleep(1)
    if subprocess.run(["systemctl", "--user", "is-active", "--quiet", "plasma-plasmashell"]).returncode != 0:
        subprocess.run(reset, capture_output=True)
        subprocess.run(["systemctl", "--user", "start", "plasma-plasmashell"], check=False)
    for _ in range(40):   # wait until Plasma accepts scripts again
        time.sleep(0.5)
        if subprocess.run(["qdbus6", "org.kde.plasmashell", "/PlasmaShell"], capture_output=True).returncode == 0:
            break
    time.sleep(3)


if __name__ == "__main__":
    if sys.argv[1:2] == ["player"]:
        player(sys.argv[2] if len(sys.argv) > 2 else "toggle")
    elif sys.argv[1:2] == ["migrate"]:
        migrate()
    elif sys.argv[1:2] == ["launcher"] and len(sys.argv) == 3:
        launcher(sys.argv[2])
    else:
        main()
