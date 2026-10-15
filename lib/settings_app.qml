// Plasmarchy settings (opened from System Settings → Appearance → Plasmarchy, or "plasmarchy configure").
// Usage: qml settings_app.qml -- <config.json> <status.json>
// Changes go to the plasmarchy script as "PLASMARCHY_SET=<key>\t<base64 value>" / "PLASMARCHY_RUN=<command>"
// (stderr); the script applies them and writes the new state to <status.json>.
import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import org.kde.kirigami as Kirigami
import "i18n.js" as I18n

ApplicationWindow {
    id: win
    function tr(text, ...args) { return I18n.tr(Qt.resolvedUrl("locale/"), text, args) }
    width: 920; height: 660
    minimumWidth: 720; minimumHeight: 520
    visible: true
    title: tr("Plasmarchy Settings")

    readonly property var args: Qt.application.arguments
    readonly property string configFile: args[args.indexOf("--") + 1]
    readonly property string statusFile: args[args.indexOf("--") + 2]
    property var cfg: null
    property int lastSeq: -1
    property string busy: ""
    property string message: ""

    function readJson(file) {
        var x = new XMLHttpRequest()
        x.open("GET", "file://" + file, false)
        x.send()
        return JSON.parse(x.responseText)
    }
    function set(key, value) {
        busy = key
        console.log("PLASMARCHY_SET=" + key + "\t" + Qt.btoa(String(value)))
    }
    function run(cmd) { console.log("PLASMARCHY_RUN=" + cmd) }
    function fontFamily(f) { return (f || "").split(",")[0] }
    function fontSize(f) { var p = (f || "").split(","); return p.length > 1 ? Number(p[1]) : 10 }

    Component.onCompleted: { try { cfg = readJson(configFile) } catch (e) {} }
    Timer {
        interval: 300; running: true; repeat: true
        onTriggered: {
            var st
            try { st = win.readJson(win.statusFile) } catch (e) { return }
            if (st.seq === win.lastSeq) return
            win.lastSeq = st.seq
            if (st.config) win.cfg = st.config
            win.busy = ""
            win.message = st.message || ""
        }
    }

    FileDialog {
        id: wallpaperDialog
        title: tr("Choose a wallpaper")
        nameFilters: [tr("Images") + " (*.png *.jpg *.jpeg *.webp)"]
        onAccepted: win.set("wallpaper.override", decodeURIComponent(selectedFile.toString().replace("file://", "")))
    }
    FileDialog {
        id: logoDialog
        title: tr("Choose a logo")
        nameFilters: [tr("Images") + " (*.svg *.png *.jpg *.jpeg *.webp)"]
        onAccepted: win.set("branding.image", decodeURIComponent(selectedFile.toString().replace("file://", "")))
    }

    // Sidebar + pages
    RowLayout {
        anchors.fill: parent
        spacing: 0
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 220
            color: Qt.darker(palette.window, 1.08)
            ListView {
                id: nav
                anchors.fill: parent
                anchors.topMargin: 12
                currentIndex: 0
                model: [
                    { icon: "preferences-desktop-theme-global", text: win.tr("Theme") },
                    { icon: "preferences-desktop-wallpaper", text: win.tr("Wallpaper") },
                    { icon: "draw-text", text: win.tr("Logo") },
                    { icon: "application-menu", text: win.tr("Menu & top bar") },
                    { icon: "preferences-desktop-font", text: win.tr("Fonts") },
                    { icon: "preferences-desktop-screensaver", text: win.tr("Screensaver") }
                ]
                delegate: ItemDelegate {
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    highlighted: ListView.isCurrentItem
                    icon.name: modelData.icon
                    text: modelData.text
                    onClicked: nav.currentIndex = index
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0
            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 24
                currentIndex: nav.currentIndex

                // --- Theme ---------------------------------------------------------------------------
                ColumnLayout {
                    spacing: 16
                    Kirigami.Heading { text: win.tr("Theme") }
                    Label { text: win.cfg ? win.tr("Active theme: {0}", win.cfg.theme.name) : ""; font.pixelSize: 16 }
                    Label {
                        Layout.fillWidth: true; wrapMode: Text.WordWrap; opacity: 0.7
                        text: win.tr("A theme sets colors, icons, wallpaper, window borders and the terminal at once.")
                    }
                    RowLayout {
                        Button { text: win.tr("Switch theme …"); icon.name: "preferences-desktop-theme-global"; highlighted: true; onClicked: win.run("pick") }
                        Button { text: "Theme Studio …"; icon.name: "preferences-desktop-color"; onClicked: win.run("studio") }
                        Button { text: win.tr("More themes …"); icon.name: "get-hot-new-stuff"; onClicked: win.run("studio catalog") }
                    }
                    Item { Layout.fillHeight: true }
                }

                // --- Wallpaper -------------------------------------------------------------------------
                Kirigami.FormLayout {
                    Kirigami.Heading { Kirigami.FormData.isSection: true; text: win.tr("Wallpaper") }
                    ColumnLayout {
                        Kirigami.FormData.label: win.tr("Image:")
                        RadioButton {
                            text: win.tr("From the theme")
                            checked: win.cfg && !win.cfg.wallpaper.override
                            onClicked: if (win.cfg.wallpaper.override) win.set("wallpaper.override", "")
                        }
                        RowLayout {
                            RadioButton {
                                text: win.tr("Own image (for every theme)")
                                checked: win.cfg && !!win.cfg.wallpaper.override
                                onClicked: wallpaperDialog.open()
                            }
                            Button { text: win.tr("Choose …"); onClicked: wallpaperDialog.open() }
                        }
                        Label {
                            visible: win.cfg && !!win.cfg.wallpaper.override
                            text: win.cfg ? win.cfg.wallpaper.override : ""
                            opacity: 0.6; elide: Text.ElideMiddle; Layout.maximumWidth: 420
                        }
                    }
                    ComboBox {
                        Kirigami.FormData.label: win.tr("Animated wallpaper:")
                        enabled: win.cfg && !win.cfg.wallpaper.override
                        readonly property var values: ["auto", "on", "off"]
                        model: [win.tr("Only themes that come with one"), win.tr("Always"), win.tr("Never")]
                        currentIndex: win.cfg ? Math.max(0, values.indexOf(win.cfg.wallpaper.animatedMode)) : 0
                        onActivated: (i) => win.set("animated.mode", values[i])
                    }
                    ComboBox {
                        Kirigami.FormData.label: win.tr("Animation for other themes:")
                        enabled: win.cfg && win.cfg.wallpaper.animatedMode === "on" && !win.cfg.wallpaper.override
                        model: win.cfg ? win.cfg.effects.map(e => e.name) : []
                        currentIndex: win.cfg ? Math.max(0, win.cfg.effects.findIndex(e => e.id === win.cfg.wallpaper.effect)) : 0
                        onActivated: (i) => win.set("animated.effect", win.cfg.effects[i].id)
                    }
                    ComboBox {
                        Kirigami.FormData.label: win.tr("Logo:")
                        readonly property var values: ["glow", "animated", "off"]
                        model: [win.tr("Glowing"), win.tr("Animated like the screensaver"), win.tr("Hidden")]
                        currentIndex: !win.cfg ? 0 : !win.cfg.wallpaper.showLogo ? 2 : win.cfg.wallpaper.logoStyle === "animated" ? 1 : 0
                        onActivated: (i) => {
                            if (values[i] === "off") win.set("animated.logo", "off")
                            else { if (!win.cfg.wallpaper.showLogo) win.set("animated.logo", "on"); win.set("animated.logostyle", values[i]) }
                        }
                    }
                }

                // --- Logo -----------------------------------------------------------------------------
                ColumnLayout {
                    spacing: 14
                    Kirigami.Heading { text: win.tr("Logo") }
                    Label {
                        Layout.fillWidth: true; wrapMode: Text.WordWrap; opacity: 0.7
                        text: win.tr("Shown by the screensaver and the animated wallpapers.")
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 170
                        color: "black"; radius: 8
                        clip: true
                        Text {
                            id: asciiPreview
                            anchors.centerIn: parent
                            color: Kirigami.Theme.highlightColor
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 9
                            lineHeight: 0.95
                            function reload() {
                                if (!win.cfg) return
                                var x = new XMLHttpRequest()
                                x.open("GET", "file://" + win.cfg.branding.ascii + "?" + Date.now(), false)
                                try { x.send(); text = x.responseText } catch (e) { text = "" }
                            }
                            Connections { target: win; function onCfgChanged() { asciiPreview.reload() } }
                        }
                    }
                    RowLayout {
                        TextField {
                            id: logoText
                            Layout.preferredWidth: 260
                            placeholderText: win.tr("Text, e.g. your name")
                            text: win.cfg && win.cfg.branding.source.indexOf("/") < 0 ? win.cfg.branding.source : ""
                            onAccepted: if (text.trim()) win.set("branding.text", text.trim())
                        }
                        Button { text: win.tr("Use text"); enabled: logoText.text.trim() !== ""; onClicked: win.set("branding.text", logoText.text.trim()) }
                        Button { text: win.tr("Use image …"); icon.name: "image-x-generic"; onClicked: logoDialog.open() }
                        Button { text: win.tr("Edit ASCII art"); icon.name: "document-edit"; onClicked: win.run("branding edit") }
                    }
                    Item { Layout.fillHeight: true }
                }

                // --- Menu & top bar -----------------------------------------------------------------------
                Kirigami.FormLayout {
                    Kirigami.Heading { Kirigami.FormData.isSection: true; text: win.tr("Menu & top bar") }
                    ColumnLayout {
                        Kirigami.FormData.label: win.tr("Windows key opens:")
                        RadioButton {
                            text: win.tr("Plasmarchy menu (centered and searchable, like Omarchy)")
                            checked: win.cfg && win.cfg.menuStyle === "plasmarchy"
                            onClicked: if (win.cfg.menuStyle !== "plasmarchy") win.set("menu.style", "plasmarchy")
                        }
                        RadioButton {
                            text: win.tr("Classic KDE application menu")
                            checked: win.cfg && win.cfg.menuStyle === "kde"
                            onClicked: if (win.cfg.menuStyle !== "kde") win.set("menu.style", "kde")
                        }
                    }
                    Switch {
                        Kirigami.FormData.label: win.tr("Music player:")
                        text: win.tr("Show in the top bar")
                        checked: win.cfg ? win.cfg.player : true
                        onToggled: win.set("player", checked ? "on" : "off")
                    }
                    Switch {
                        Kirigami.FormData.label: win.tr("Hot corner:")
                        text: win.tr("Top left corner shows all windows")
                        checked: win.cfg ? win.cfg.hotcorner : true
                        onToggled: win.set("hotcorner", checked ? "on" : "off")
                    }
                }

                // --- Fonts ------------------------------------------------------------------------------
                Kirigami.FormLayout {
                    id: fontsPage
                    readonly property var families: Qt.fontFamilies()
                    Kirigami.Heading { Kirigami.FormData.isSection: true; text: win.tr("Fonts") }
                    RowLayout {
                        Kirigami.FormData.label: win.tr("Interface:")
                        ComboBox {
                            id: uiFamily
                            Layout.preferredWidth: 280
                            model: fontsPage.families
                            currentIndex: win.cfg ? Math.max(0, fontsPage.families.indexOf(win.fontFamily(win.cfg.fonts.ui))) : 0
                            onActivated: win.set("font.ui", currentText + "," + uiSize.value)
                        }
                        SpinBox { id: uiSize; from: 7; to: 20; value: win.cfg ? win.fontSize(win.cfg.fonts.ui) : 10
                                  onValueModified: win.set("font.ui", uiFamily.currentText + "," + value) }
                    }
                    RowLayout {
                        Kirigami.FormData.label: win.tr("Monospace:")
                        ComboBox {
                            id: monoFamily
                            Layout.preferredWidth: 280
                            model: fontsPage.families
                            currentIndex: win.cfg ? Math.max(0, fontsPage.families.indexOf(win.fontFamily(win.cfg.fonts.mono))) : 0
                            onActivated: win.set("font.mono", currentText + "," + monoSize.value)
                        }
                        SpinBox { id: monoSize; from: 7; to: 20; value: win.cfg ? win.fontSize(win.cfg.fonts.mono) : 10
                                  onValueModified: win.set("font.mono", monoFamily.currentText + "," + value) }
                    }
                    Button {
                        text: win.tr("Reset to Plasmarchy defaults")
                        onClicked: { win.set("font.ui", "Noto Sans,10"); win.set("font.mono", "JetBrainsMono Nerd Font,10") }
                    }
                    Label {
                        text: win.tr("Some apps only pick up a new font after a restart.")
                        opacity: 0.6
                    }
                }

                // --- Screensaver ---------------------------------------------------------------------------
                Kirigami.FormLayout {
                    Kirigami.Heading { Kirigami.FormData.isSection: true; text: win.tr("Screensaver") }
                    RowLayout {
                        Kirigami.FormData.label: win.tr("Start after:")
                        SpinBox { from: 0; to: 120; value: win.cfg ? win.cfg.screensaverTimeout : 5
                                  onValueModified: win.set("screensaver.timeout", value) }
                        Label { text: win.tr("minutes (0 = never automatically)"); opacity: 0.7 }
                    }
                    Button { text: win.tr("Start now"); icon.name: "media-playback-start"; onClicked: win.run("screensaver") }
                }
            }

            // status line
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 12
                BusyIndicator { visible: win.busy !== ""; running: visible; implicitWidth: 22; implicitHeight: 22 }
                Label { text: win.busy !== "" ? win.tr("Applying …") : win.message; opacity: 0.7; Layout.fillWidth: true; elide: Text.ElideRight }
            }
        }
    }
}
