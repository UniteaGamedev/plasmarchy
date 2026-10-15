// Renders a still of the animated wallpaper (for theme previews and lock screen images).
// Usage: qml wallpaper_preview.qml -- <scene.qml url> <out.png> <width> <height> <seconds> <json settings>
import QtQuick
import QtQuick.Window

Window {
    id: win
    readonly property var args: Qt.application.arguments
    readonly property var opts: JSON.parse(args[args.length - 1])
    width: Number(args[args.length - 4]); height: Number(args[args.length - 3])
    visible: true
    color: "black"

    Loader {
        id: loader
        anchors.fill: parent
        source: win.args[win.args.length - 6]
        onLoaded: { for (var k in win.opts) item[k] = win.opts[k] }
    }
    Timer {
        running: loader.status === Loader.Ready
        interval: Number(win.args[win.args.length - 2]) * 1000
        onTriggered: loader.grabToImage(r => { r.saveToFile(win.args[win.args.length - 5]); Qt.quit() })
    }
}
