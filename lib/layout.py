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
MASKED_TRAY = ["org.kde.plasma.bluetooth", "org.kde.plasma.battery", "org.kde.plasma.volume",
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
    var kick = top.addWidget("org.kde.plasma.kickoff");
    kick.currentConfigGroup = ["General"]; kick.writeConfig("icon", "view-app-grid-symbolic");
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
    var ai = top.addWidget("org.plasmarchy.aiusage");
    ai.globalShortcut = "Meta+Shift+A";     // open the AI assistant from the keyboard
    var tray = top.addWidget("org.kde.plasma.systemtray");
    tray.currentConfigGroup = ["General"];
    tray.writeConfig("hiddenItems", {json.dumps(HIDDEN_TRAY)});
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
            var kick = p.widgets().filter(w => w.type == "org.kde.plasma.kickoff")[0];
            var force = {json.dumps(force)};
            if (kick) force.widgets.push({{"name": "org.kde.plasma.kickoff", "id": kick.id,
                                           "method": {{"mask": true, "multiEffect": false}}, "reload": false}});
            p.widgets().filter(w => w.type == "luisbocanegra.panel.colorizer").forEach(c => {{
                c.currentConfigGroup = ["General"];
                c.writeConfig("forceForegroundColor", JSON.stringify(force));
            }});
        }});''')
    restart_plasma()
    print(tr("Panels set up."))


def restart_plasma():
    subprocess.run(["systemctl", "--user", "restart", "plasma-plasmashell"], check=False)
    for _ in range(40):   # wait until Plasma accepts scripts again
        time.sleep(0.5)
        if subprocess.run(["qdbus6", "org.kde.plasmashell", "/PlasmaShell"], capture_output=True).returncode == 0:
            break
    time.sleep(3)


if __name__ == "__main__":
    main()
