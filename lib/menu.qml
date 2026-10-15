// Plasmarchy menu, modeled on Omarchy's: main entries with sub menus in a centered box.
// Typing searches all entries and installed apps; arrow keys navigate; Enter/→ opens, Esc/← goes back.
// Usage: qml menu.qml -- <menu.json>   (written by menu.py, includes the theme colors)
// Output (stderr): "PLASMARCHY_MENU=<shell command>" for the chosen entry
import QtQuick
import QtQuick.Window
import QtQuick.Controls
import org.kde.kirigami as Kirigami

Window {
    id: win
    visible: true
    visibility: Window.FullScreen
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    color: "transparent"
    title: "Plasmarchy Menu"

    readonly property var args: Qt.application.arguments
    property var menuData: ({ menu: [], apps: [], labels: {} })
    property var c: ({ background: "#111111", foreground: "#dddddd", accent: "#88aaff", muted: "#666666" })
    property var stack: []              // opened sub menus: [{label, items}]
    readonly property string mono: "JetBrainsMono Nerd Font"
    readonly property real s: Math.max(1, Screen.height / 1080)   // size relative to a 1080p screen
    property bool closing: false

    function read(file) {
        var x = new XMLHttpRequest()
        x.open("GET", "file://" + file, false)
        x.send()
        return JSON.parse(x.responseText)
    }
    function label(key) { return (menuData.labels || {})[key] || key }

    // Every leaf entry with its path ("Style › Theme Studio") - for searching
    function flatten(items, path) {
        var out = []
        for (var i = 0; i < items.length; i++) {
            var it = items[i]
            if (it.items) out = out.concat(flatten(it.items, path.concat([it.label])))
            else if (it.cmd) out.push(Object.assign({}, it, { detail: path.join(" › ") }))
        }
        return out
    }
    readonly property var allEntries: flatten(menuData.menu, [])

    function score(entry, q) {
        var l = entry.label.toLowerCase()
        if (l === q) return 100
        if (l.indexOf(q) === 0) return 80
        if (l.split(/[\s\-]+/).some(w => w.indexOf(q) === 0)) return 60
        if (l.indexOf(q) >= 0) return 40
        if ((entry.detail || "").toLowerCase().indexOf(q) >= 0) return 20
        if ((entry.keywords || "").indexOf(q) >= 0) return 15
        return 0
    }

    readonly property var current: {
        var q = search.text.trim().toLowerCase()
        if (q !== "") {
            var res = []
            var pool = allEntries.concat(menuData.apps)
            for (var i = 0; i < pool.length; i++) {
                var sc = score(pool[i], q)
                if (sc > 0) res.push({ e: pool[i], sc: sc + (pool[i].iconName !== undefined ? 0 : 5) })
            }
            res.sort((a, b) => b.sc - a.sc || a.e.label.localeCompare(b.e.label))
            res = res.slice(0, 40).map(r => r.e)
            res.push({ id: "krunner", icon: String.fromCodePoint(0xF0349),
                       label: label("krunner").replace("{0}", search.text.trim()),
                       cmd: "qdbus6 org.kde.krunner /App org.kde.krunner.App.query " + JSON.stringify(search.text.trim()) })
            return res
        }
        if (stack.length) return stack[stack.length - 1].items
        return menuData.menu
    }
    onCurrentChanged: list.currentIndex = 0

    function activate(entry) {
        if (!entry) return
        if (entry.apps) { open({ label: entry.label, items: menuData.apps }); return }
        if (entry.items) { open(entry); return }
        if (entry.cmd) finish(entry.cmd)
    }
    function open(entry) { stack = stack.concat([{ label: entry.label, items: entry.items }]); search.text = "" }
    function back() {
        if (search.text !== "") { search.text = ""; return }
        if (stack.length) { stack = stack.slice(0, -1); return }
        finish("")
    }
    function finish(cmd) {
        if (closing) return
        closing = true
        if (cmd) console.log("PLASMARCHY_MENU=" + cmd)
        fadeOut.start()
    }

    Component.onCompleted: {
        try { menuData = read(args[args.length - 1]) } catch (e) { console.log("menu data: " + e) }
        if (menuData.colors) c = menuData.colors
        search.forceActiveFocus()
    }
    onActiveChanged: if (!active && !closing) finish("")   // clicked elsewhere / switched away

    MouseArea { anchors.fill: parent; onClicked: win.finish("") }   // click outside closes

    Rectangle {
        id: box
        width: Math.min(win.width - 40, 620 * win.s)
        height: header.height + list.height + 3 * win.s
        x: (win.width - width) / 2
        y: win.height * 0.22
        color: win.c.background
        border.color: win.c.accent
        border.width: 2
        radius: 8
        opacity: 0
        scale: 0.97
        Component.onCompleted: fadeIn.start()
        MouseArea { anchors.fill: parent }   // clicks inside don't close

        Column {
            id: header
            width: parent.width
            Row {
                width: parent.width
                height: 52 * win.s
                leftPadding: 18 * win.s
                spacing: 10 * win.s
                Text {   // breadcrumb of opened sub menus
                    anchors.verticalCenter: parent.verticalCenter
                    visible: win.stack.length > 0 && search.text === ""
                    text: win.stack.map(x => x.label).join(" › ") + "  ›"
                    color: win.c.accent
                    font.family: win.mono; font.pixelSize: 15 * win.s
                }
                TextField {
                    id: search
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - x - 18 * win.s
                    placeholderText: win.stack.length ? "" : win.label("search")
                    placeholderTextColor: Qt.alpha(win.c.foreground, 0.4)
                    color: win.c.foreground
                    font.family: win.mono; font.pixelSize: 16 * win.s
                    background: Item {}
                    selectByMouse: true
                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Down) { list.incrementCurrentIndex(); event.accepted = true }
                        else if (event.key === Qt.Key_Up) { list.decrementCurrentIndex(); event.accepted = true }
                        else if (event.key === Qt.Key_PageDown) { list.currentIndex = Math.min(list.count - 1, list.currentIndex + 8); event.accepted = true }
                        else if (event.key === Qt.Key_PageUp) { list.currentIndex = Math.max(0, list.currentIndex - 8); event.accepted = true }
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { win.activate(win.current[list.currentIndex]); event.accepted = true }
                        else if (event.key === Qt.Key_Right && search.text === "") { var e = win.current[list.currentIndex]; if (e && (e.items || e.apps)) win.activate(e); event.accepted = true }
                        else if (event.key === Qt.Key_Escape || (event.key === Qt.Key_Left || event.key === Qt.Key_Backspace) && search.text === "") { win.back(); event.accepted = true }
                    }
                }
            }
            Rectangle { width: parent.width; height: 1; color: Qt.alpha(win.c.accent, 0.35) }
        }

        ListView {
            id: list
            anchors.top: header.bottom
            anchors.topMargin: 2 * win.s
            width: parent.width
            height: Math.min(count, 10) * 44 * win.s + (count === 0 ? 44 * win.s : 0)
            clip: true
            model: win.current
            highlightMoveDuration: 90
            boundsBehavior: Flickable.StopAtBounds
            keyNavigationWraps: true

            Text {
                visible: list.count === 0
                anchors.centerIn: parent
                text: win.label("empty")
                color: win.c.muted
                font.family: win.mono; font.pixelSize: 14 * win.s
            }

            delegate: Item {
                id: row
                required property var modelData
                required property int index
                readonly property bool sel: ListView.isCurrentItem
                width: list.width
                height: 44 * win.s
                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: 6 * win.s; anchors.rightMargin: 6 * win.s
                    radius: 5
                    color: row.sel ? Qt.alpha(win.c.accent, 0.16) : "transparent"
                }
                Rectangle {   // accent marker of the selected row
                    visible: row.sel
                    x: 6 * win.s; width: 3; height: parent.height - 14 * win.s
                    anchors.verticalCenter: parent.verticalCenter
                    radius: 1.5
                    color: win.c.accent
                }
                Item {
                    id: iconBox
                    x: 18 * win.s; width: 26 * win.s; height: parent.height
                    Text {
                        anchors.centerIn: parent
                        visible: row.modelData.iconName === undefined
                        text: row.modelData.icon || ""
                        color: row.sel ? win.c.accent : win.c.foreground
                        font.family: win.mono; font.pixelSize: 19 * win.s
                    }
                    Kirigami.Icon {
                        anchors.centerIn: parent
                        visible: row.modelData.iconName !== undefined
                        width: 22 * win.s; height: width
                        source: row.modelData.iconName || "application-x-executable"
                        fallback: "application-x-executable"
                    }
                }
                Text {
                    id: name
                    anchors.left: iconBox.right; anchors.leftMargin: 12 * win.s
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.label
                    color: row.sel ? win.c.accent : win.c.foreground
                    font.family: win.mono; font.pixelSize: 15 * win.s
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, row.width * 0.6)
                }
                Text {   // where it lives (search results) or the app's generic name
                    anchors.left: name.right; anchors.leftMargin: 12 * win.s
                    anchors.right: arrow.left; anchors.rightMargin: 8 * win.s
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.detail || ""
                    color: win.c.muted
                    font.family: win.mono; font.pixelSize: 12 * win.s
                    elide: Text.ElideRight
                }
                Text {
                    id: arrow
                    anchors.right: parent.right; anchors.rightMargin: 18 * win.s
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.items || row.modelData.apps ? "›" : ""
                    color: win.c.muted
                    font.family: win.mono; font.pixelSize: 18 * win.s
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: list.currentIndex = row.index
                    onClicked: win.activate(row.modelData)
                }
            }
        }
    }

    ParallelAnimation {
        id: fadeIn
        NumberAnimation { target: box; property: "opacity"; to: 1; duration: 140; easing.type: Easing.OutCubic }
        NumberAnimation { target: box; property: "scale"; to: 1; duration: 160; easing.type: Easing.OutCubic }
    }
    SequentialAnimation {
        id: fadeOut
        ParallelAnimation {
            NumberAnimation { target: box; property: "opacity"; to: 0; duration: 90 }
            NumberAnimation { target: box; property: "scale"; to: 0.97; duration: 90 }
        }
        ScriptAction { script: Qt.quit() }
    }
}
