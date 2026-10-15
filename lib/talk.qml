// Conversation overlay: orb in the accent color + captions, bottom center.
// Usage (from talk.py): qml talk.qml -- <status.json> <colors.json>
// Clicks pass through (blocks nothing); stop via the hotkey or by saying "stop".
import QtQuick
import QtQuick.Window
import "i18n.js" as I18n

Window {
    id: win
    visible: true
    visibility: Window.FullScreen
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.WindowTransparentForInput | Qt.Tool
    color: "transparent"
    title: tr("AI conversation")

    readonly property var args: Qt.application.arguments
    function tr(text, ...args) { return I18n.tr(Qt.resolvedUrl("locale/"), text, args) }
    property var st: ({ state: "listening", user: "", answer: "", note: "" })
    property var c: ({ background: "#111111", foreground: "#dddddd", accent: "#88aaff", muted: "#666666" })
    readonly property var labels: ({ listening: tr("Listening …"), thinking: tr("Thinking …"), speaking: "",
                                     error: "", done: "" })

    function read(file) {
        var x = new XMLHttpRequest()
        x.open("GET", "file://" + file, false)
        x.send()
        return JSON.parse(x.responseText)
    }

    Component.onCompleted: { try { c = read(args[args.length - 1]) } catch (e) {} }

    Timer {
        interval: 150; running: true; repeat: true
        onTriggered: {
            try { win.st = win.read(win.args[win.args.length - 2]) } catch (e) { return }
            if (win.st.state === "done") fadeOut.start()
        }
    }

    Item {
        id: stage
        anchors.fill: parent
        opacity: 0
        Component.onCompleted: fadeIn.start()
        NumberAnimation on opacity { id: fadeIn; running: false; to: 1; duration: 220; easing.type: Easing.OutCubic }
        NumberAnimation on opacity { id: fadeOut; running: false; to: 0; duration: 260
                                     onFinished: Qt.quit() }

        Column {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 120 }
            spacing: 18

            // --- Orb ----------------------------------------------------------------------------
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 96; height: 96
                Rectangle {          // Glow
                    anchors.centerIn: parent
                    width: orb.width * 1.6; height: width; radius: width / 2
                    color: win.c.accent
                    opacity: 0.18 * orb.scale
                }
                Rectangle {
                    id: orb
                    anchors.centerIn: parent
                    width: 64; height: 64; radius: 32
                    color: win.st.state === "error" ? win.c.muted : win.c.accent
                    border.color: win.c.foreground
                    border.width: 2
                    SequentialAnimation on scale {   // breathe (listening) or pulse (speaking)
                        loops: Animation.Infinite
                        running: win.st.state === "listening" || win.st.state === "speaking"
                        NumberAnimation { to: win.st.state === "speaking" ? 1.18 : 1.1
                                          duration: win.st.state === "speaking" ? 260 : 900; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 0.94; duration: win.st.state === "speaking" ? 260 : 900; easing.type: Easing.InOutSine }
                    }
                }
                Rectangle {          // thinking: orbiting dot
                    visible: win.st.state === "thinking"
                    width: 12; height: 12; radius: 6
                    color: win.c.foreground
                    x: 48 - 6 + Math.cos(angle) * 44
                    y: 48 - 6 + Math.sin(angle) * 44
                    property real angle: 0
                    NumberAnimation on angle { from: 0; to: Math.PI * 2; duration: 900; loops: Animation.Infinite
                                               running: win.st.state === "thinking" }
                }
            }

            // --- Captions in an Omarchy frame --------------------------------------------------
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(win.width * 0.55, Math.max(260, captions.implicitWidth + 48))
                height: captions.implicitHeight + 32
                radius: 10
                color: Qt.alpha(win.c.background, 0.92)
                border.color: win.c.accent
                border.width: 2
                Column {
                    id: captions
                    anchors.centerIn: parent
                    width: parent.width - 48
                    spacing: 8
                    Text {
                        width: parent.width
                        visible: text !== ""
                        text: win.labels[win.st.state] || ""
                        color: win.c.muted
                        font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 15
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Text {
                        width: parent.width
                        visible: win.st.user !== ""
                        text: "„" + win.st.user + "“"
                        color: win.c.muted
                        wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                        font.pixelSize: 15
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Text {
                        width: parent.width
                        visible: win.st.note !== ""
                        text: win.st.note
                        color: win.c.accent
                        wrapMode: Text.WordWrap
                        font.pixelSize: 14
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Text {
                        width: parent.width
                        visible: win.st.answer !== ""
                        text: win.st.answer
                        color: win.c.foreground
                        wrapMode: Text.WordWrap; maximumLineCount: 6; elide: Text.ElideRight
                        textFormat: Text.MarkdownText
                        font.pixelSize: 17
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }
    }
}
