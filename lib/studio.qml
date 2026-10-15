// Plasmarchy Theme Studio: create, edit and delete your own themes.
// Usage: qml studio.qml -- <manifest.json> <status.json>
// Actions go to the plasmarchy script as "PLASMARCHY_ACTION=<verb> <arg>" (stderr);
// the result comes back via <status.json> (polled here).
import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import "i18n.js" as I18n

ApplicationWindow {
    id: win
    function tr(text, ...args) { return I18n.tr(Qt.resolvedUrl("locale/"), text, args) }
    width: 1240
    height: 820
    minimumWidth: 1000
    minimumHeight: 680
    visible: true
    title: "Plasmarchy – Theme Studio"

    readonly property var args: Qt.application.arguments
    readonly property string manifestFile: args[args.indexOf("--") + 1]
    readonly property string statusFile: args[args.indexOf("--") + 2]
    readonly property bool openCatalog: args.indexOf("catalog") > args.indexOf("--")

    property var manifest: ({ themes: [], folderColors: [], paletteKeys: [] })
    property int selected: -1
    readonly property bool readOnly: theme !== null && theme !== undefined && !theme.user   // built-in themes
    property var draft: null            // working copy of the selected theme
    property bool dirty: false
    property int lastSeq: 0
    property string pendingSelect: ""
    property string message: ""
    property bool messageOk: true

    readonly property var theme: selected >= 0 && selected < manifest.themes.length ? manifest.themes[selected] : null
    readonly property var p: draft ? draft.palette : ({})

    // palette labels (Omarchy key -> readable name)
    readonly property var labels: ({
        accent: tr("Accent"), selection: tr("Selection"), muted: tr("Muted"),
        background: tr("Background"), dark_background: tr("Background dark"), darker_background: tr("Background darker"),
        lighter_background: tr("Background lighter"), foreground: tr("Text"), dark_foreground: tr("Text dark"),
        light_foreground: tr("Text light"), bright_foreground: tr("Text highlighted"),
        red: tr("Red"), yellow: tr("Yellow"), orange: tr("Orange"), green: tr("Green"), cyan: tr("Cyan"), blue: tr("Blue"),
        magenta: tr("Magenta"), brown: tr("Brown"), bright_red: tr("Red light"), bright_yellow: tr("Yellow light"),
        bright_green: tr("Green light"), bright_cyan: tr("Cyan light"), bright_blue: tr("Blue light"), bright_magenta: tr("Magenta light")
    })

    function readJson(file) {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + file, false)
        xhr.send()
        return JSON.parse(xhr.responseText)
    }

    function loadManifest(selectSlug) {
        manifest = readJson(manifestFile)
        var slug = selectSlug || (theme ? theme.slug : manifest.current)
        var idx = manifest.themes.findIndex(t => t.slug === slug)
        select(idx >= 0 ? idx : 0)
    }

    function select(idx) {
        selected = idx
        var t = manifest.themes[idx]
        draft = t ? { slug: t.slug, name: t.name, mode: t.light ? "light" : "dark", folder: t.folder,
                      animation: t.animation || "",
                      palette: Object.assign({}, t.palette), backgrounds: t.backgrounds.slice() } : null
        dirty = false
    }

    // Always assign new objects, otherwise QML does not update dependent bindings
    function touch() {
        draft = Object.assign({}, draft, { palette: Object.assign({}, draft.palette),
                                           backgrounds: draft.backgrounds.slice() })
        dirty = true
    }
    function setColor(key, value) { draft.palette[key] = value; touch() }

    // send an action to the script; JSON is made ASCII-safe and base64-encoded
    function send(verb, arg) {
        message = "…"
        console.log("PLASMARCHY_ACTION=" + verb + " " + arg)
    }
    function save(thenApply) {
        var json = JSON.stringify(draft).replace(/[\u0080-￿]/g,
                     c => "\\u" + ("0000" + c.charCodeAt(0).toString(16)).slice(-4))
        pendingApply = thenApply
        send("save", Qt.btoa(json))
    }
    property bool pendingApply: false

    Timer {
        interval: 400; running: true; repeat: true
        onTriggered: {
            var st
            try { st = win.readJson(win.statusFile) } catch (e) { return }
            if (st.seq === win.lastSeq) return
            win.lastSeq = st.seq
            win.message = st.message
            win.messageOk = st.ok
            win.loadManifest(st.ok && st.slug ? st.slug : "")
            if (catalogDialog.opened && ["catalog", "install", "uninstall"].indexOf(st.verb) >= 0) {
                try { win.catalog = win.readJson(win.manifestFile.replace("themes.json", "catalog.json")) } catch (e) { win.catalog = { error: st.message, themes: [] } }
            }
            if (st.ok && win.pendingApply && st.verb === "save") {
                win.pendingApply = false
                // The script already re-applies the active theme after saving
                if (win.manifest.current !== st.slug) win.send("apply", st.slug)
            }
        }
    }

    Component.onCompleted: {
        loadManifest("")
        if (openCatalog) { catalogDialog.open(); send("catalog", "list") }
    }

    ColorDialog {
        id: colorDialog
        property string key: ""
        onAccepted: win.setColor(key, selectedColor.toString().slice(0, 7))
    }
    FileDialog {
        id: imageDialog
        title: tr("Add wallpaper")
        nameFilters: [tr("Images") + " (*.png *.jpg *.jpeg *.webp)"]
        fileMode: FileDialog.OpenFiles
        onAccepted: {
            for (var i = 0; i < selectedFiles.length; i++)
                win.draft.backgrounds.push(decodeURIComponent(selectedFiles[i].toString().replace("file://", "")))
            win.touch()
        }
    }
    Dialog {
        id: newDialog
        title: tr("New theme")
        anchors.centerIn: parent
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        ColumnLayout {
            Label { text: tr("Name of the new theme (based on the active theme)") }
            TextField { id: newName; Layout.preferredWidth: 320; placeholderText: tr("e.g. My Jade") }
        }
        onAccepted: if (newName.text.trim()) { win.pendingSelect = ""; win.send("new", newName.text.trim()); newName.text = "" }
    }
    // --- Theme catalog: more themes to install -----------------------------------------------------
    property var catalog: null          // {themes: [...]} from themestore.py
    Dialog {
        id: catalogDialog
        title: tr("More themes")
        anchors.centerIn: parent
        width: Math.min(win.width - 80, 860)
        height: Math.min(win.height - 80, 620)
        modal: true
        standardButtons: Dialog.Close
        ColumnLayout {
            anchors.fill: parent
            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                opacity: 0.7
                text: win.catalog === null ? tr("Loading the theme catalog …")
                    : win.catalog.error ? win.catalog.error
                    : tr("Themes from the Plasmarchy catalog on GitHub. Anyone can add one with a pull request.")
            }
            GridView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                cellWidth: width / Math.max(1, Math.floor(width / 270))
                cellHeight: 230
                model: win.catalog && win.catalog.themes ? win.catalog.themes : []
                delegate: Item {
                    required property var modelData
                    width: GridView.view.cellWidth; height: 230
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 8
                        spacing: 6
                        Image {
                            Layout.fillWidth: true; Layout.preferredHeight: 140
                            source: modelData.thumbPath ? "file://" + modelData.thumbPath : ""
                            fillMode: Image.PreserveAspectCrop; asynchronous: true
                        }
                        RowLayout {
                            Label { text: modelData.name; font.bold: true; Layout.fillWidth: true; elide: Text.ElideRight }
                            Label { visible: !!modelData.animation; text: tr("animated"); opacity: 0.55; font.pixelSize: 11 }
                        }
                        RowLayout {
                            Label { text: (modelData.size / 1e6).toFixed(1) + " MB"; opacity: 0.5; font.pixelSize: 11; Layout.fillWidth: true }
                            Button {
                                text: modelData.installed ? tr("Uninstall") : tr("Install")
                                highlighted: !modelData.installed
                                onClicked: win.send(modelData.installed ? "uninstall" : "install", modelData.slug)
                            }
                        }
                    }
                }
            }
        }
    }

    Dialog {
        id: deleteDialog
        title: tr("Delete theme?")
        anchors.centerIn: parent
        modal: true
        standardButtons: Dialog.Yes | Dialog.No
        Label {
            text: !win.theme ? "" : win.theme.user ? tr("“{0}” will be deleted permanently.", win.theme.name)
                : tr("“{0}” will be removed. You can get it back any time under “More themes”.", win.theme.name)
        }
        onAccepted: win.send("delete", win.theme.slug)
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // --- Theme list ----------------------------------------------------------------------
        Pane {
            Layout.fillHeight: true
            Layout.preferredWidth: 270
            padding: 12
            ColumnLayout {
                anchors.fill: parent
                spacing: 8
                Label { text: "Themes"; font.pixelSize: 20; font.bold: true }
                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: win.manifest.themes
                    currentIndex: win.selected
                    spacing: 2
                    delegate: ItemDelegate {
                        required property var modelData
                        required property int index
                        width: ListView.view.width
                        highlighted: index === win.selected
                        onClicked: win.select(index)
                        contentItem: RowLayout {
                            spacing: 8
                            Rectangle { width: 16; height: 16; radius: 8; color: modelData.palette.accent; border.color: modelData.palette.background }
                            Label { text: modelData.name; Layout.fillWidth: true; elide: Text.ElideRight
                                    font.bold: modelData.slug === win.manifest.current }
                            Label { visible: modelData.user; text: tr("custom"); opacity: 0.6; font.pixelSize: 11 }
                        }
                    }
                }
                Button { text: "+ " + tr("New theme"); Layout.fillWidth: true; onClicked: newDialog.open() }
                Button {
                    text: win.theme && win.theme.user ? tr("Delete") : tr("Remove")
                    Layout.fillWidth: true
                    enabled: win.theme && win.theme.slug !== win.manifest.current
                    onClicked: deleteDialog.open()
                    ToolTip.visible: hovered && win.theme && win.theme.slug === win.manifest.current
                    ToolTip.text: tr("The active theme can't be removed")
                }
                Button {
                    text: tr("More themes …"); Layout.fillWidth: true; icon.name: "get-hot-new-stuff"
                    onClicked: { win.catalog = null; catalogDialog.open(); win.send("catalog", "list") }
                }
            }
        }

        // --- Editor ----------------------------------------------------------------------------
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth
            visible: win.draft !== null

            ColumnLayout {
                width: parent.width - 32
                x: 16
                spacing: 14

                Item { height: 4 }
                RowLayout {
                    Layout.fillWidth: true
                    TextField {
                        Layout.fillWidth: true
                        font.pixelSize: 20
                        readOnly: win.readOnly
                        text: win.draft ? win.draft.name : ""
                        onTextEdited: { win.draft.name = text; win.dirty = true }
                    }
                }

                RowLayout {
                    spacing: 18
                    Label { text: tr("Mode") }
                    ComboBox {
                        enabled: !win.readOnly
                        model: [tr("Dark"), tr("Light")]
                        currentIndex: win.draft && win.draft.mode === "light" ? 1 : 0
                        onActivated: (i) => { win.draft.mode = i === 1 ? "light" : "dark"; win.touch() }
                    }
                    Label { text: tr("Folder color") }
                    ComboBox {
                        id: folderBox
                        enabled: !win.readOnly
                        model: win.manifest.folderColors
                        currentIndex: win.draft ? win.manifest.folderColors.indexOf(win.draft.folder) : 0
                        onActivated: (i) => { win.draft.folder = win.manifest.folderColors[i]; win.touch() }
                    }
                    Label { text: tr("Animated wallpaper") }
                    ComboBox {
                        enabled: !win.readOnly
                        readonly property var values: ["", "aurora", "particles", "rain", "logo"]
                        model: [tr("None (still image)"), tr("Aurora"), tr("Particles"), tr("Code rain"), tr("Logo animation")]
                        currentIndex: win.draft ? Math.max(0, values.indexOf(win.draft.animation || "")) : 0
                        onActivated: (i) => { win.draft.animation = values[i]; win.touch() }
                    }
                }

                // live preview
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 190
                    radius: 12
                    color: win.p.background || "#000"
                    border.color: win.p.selection || "#333"
                    clip: true
                    Rectangle {  // title bar
                        width: parent.width; height: 34; color: win.p.darker_background || "#000"
                        Row {
                            anchors.verticalCenter: parent.verticalCenter; x: 14; spacing: 7
                            Repeater { model: ["red", "yellow", "green"]
                                delegate: Rectangle { required property string modelData
                                    width: 11; height: 11; radius: 6; color: win.p[modelData] || "#888" } }
                        }
                        Text { anchors.centerIn: parent; text: win.draft ? win.draft.name : ""
                               color: win.p.foreground || "#fff"; font.family: "JetBrainsMono Nerd Font" }
                    }
                    Column {
                        x: 18; y: 50; spacing: 8
                        Text { text: tr("Text  ·  muted  ·  highlighted"); color: win.p.foreground || "#fff"; font.pixelSize: 15 }
                        Row {
                            spacing: 10
                            Rectangle { width: 120; height: 30; radius: 6; color: win.p.accent || "#888"
                                Text { anchors.centerIn: parent; text: tr("Accent"); color: win.p.darker_background || "#000"; font.bold: true } }
                            Rectangle { width: 120; height: 30; radius: 6; color: win.p.selection || "#444"
                                Text { anchors.centerIn: parent; text: tr("Selection"); color: win.p.foreground || "#fff" } }
                            Rectangle { width: 120; height: 30; radius: 6; color: win.p.lighter_background || "#333"
                                Text { anchors.centerIn: parent; text: "Button"; color: win.p.foreground || "#fff" } }
                        }
                        Text {  // terminal line
                            font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 14; textFormat: Text.RichText
                            text: win.draft ? ("<span style='color:" + win.p.green + "'>user@cachyos</span> "
                                  + "<span style='color:" + win.p.blue + "'>~/projects</span> "
                                  + "<span style='color:" + win.p.magenta + "'>git:(main)</span> "
                                  + "<span style='color:" + win.p.yellow + "'>⚡</span> "
                                  + "<span style='color:" + win.p.foreground + "'>plasmarchy theme</span> "
                                  + "<span style='color:" + win.p.red + "'>--error</span> "
                                  + "<span style='color:" + win.p.cyan + "'>\"ok\"</span>") : ""
                        }
                        Text { text: tr("muted hint text"); color: win.p.muted || "#888"; font.pixelSize: 13 }
                    }
                }

                Label { text: tr("Colors"); font.pixelSize: 16; font.bold: true }
                GridLayout {
                    Layout.fillWidth: true
                    columns: 3
                    columnSpacing: 18
                    rowSpacing: 6
                    Repeater {
                        model: win.manifest.paletteKeys
                        delegate: RowLayout {
                            required property string modelData
                            Layout.fillWidth: true
                            spacing: 8
                            Rectangle {
                                width: 30; height: 30; radius: 6
                                color: win.p[modelData] || "transparent"
                                border.color: "#80808080"
                                MouseArea { anchors.fill: parent; enabled: !win.readOnly; cursorShape: Qt.PointingHandCursor
                                    onClicked: { colorDialog.key = modelData; colorDialog.selectedColor = win.p[modelData] || "#000000"; colorDialog.open() } }
                            }
                            Label { text: win.labels[modelData] || modelData; Layout.preferredWidth: 140; elide: Text.ElideRight }
                            TextField {
                                Layout.preferredWidth: 90
                                readOnly: win.readOnly
                                font.family: "JetBrainsMono Nerd Font"
                                text: win.p[modelData] || ""
                                validator: RegularExpressionValidator { regularExpression: /#[0-9a-fA-F]{0,6}/ }
                                onEditingFinished: if (/^#[0-9a-fA-F]{6}$/.test(text)) win.setColor(modelData, text.toLowerCase())
                            }
                        }
                    }
                }

                RowLayout {
                    Label { text: tr("Wallpapers"); font.pixelSize: 16; font.bold: true }
                    Item { Layout.fillWidth: true }
                    Button { text: tr("Add image…"); visible: !win.readOnly; onClicked: imageDialog.open() }
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 10
                    Repeater {
                        model: win.draft ? win.draft.backgrounds : []
                        delegate: Item {
                            required property string modelData
                            required property int index
                            width: 180; height: 112
                            Image { anchors.fill: parent; source: "file://" + modelData; sourceSize.width: 360
                                    fillMode: Image.PreserveAspectCrop; asynchronous: true }
                            RoundButton {
                                anchors { top: parent.top; right: parent.right; margins: 4 }
                                text: "✕"; width: 28; height: 28
                                visible: !win.readOnly
                                onClicked: { win.draft.backgrounds.splice(index, 1); win.touch() }
                            }
                        }
                    }
                }
                Item { height: 70 }
            }
        }
    }

    footer: ToolBar {
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            Label {
                text: win.message
                color: win.messageOk ? palette.windowText : "#e05555"
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            // Built-in themes are read-only: duplicate one to customize it
            Button { text: tr("Duplicate"); visible: win.readOnly; enabled: win.draft !== null
                     onClicked: { win.pendingSelect = ""; win.send("duplicate", win.theme.slug) } }
            Button { text: tr("Apply"); visible: win.readOnly; highlighted: true; enabled: win.draft !== null
                     onClicked: win.send("apply", win.theme.slug) }
            Button { text: tr("Discard"); visible: !win.readOnly; enabled: win.dirty; onClicked: win.select(win.selected) }
            Button { text: tr("Save"); visible: !win.readOnly; enabled: win.draft !== null && win.dirty; onClicked: win.save(false) }
            Button { text: tr("Save & apply"); visible: !win.readOnly; highlighted: true; enabled: win.draft !== null; onClicked: win.save(true) }
        }
    }
}
