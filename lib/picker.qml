// Plasmarchy theme picker in Omarchy style: slanted previews as a carousel.
// Usage: qml picker.qml -- <manifest.json>
// Output (stderr): "PLASMARCHY_CHOICE=<theme>" or "__restore" / "__nextbg" / "__studio"
// Keys: Left/Right select, Enter apply, N next wallpaper, S Theme Studio, R restore, Esc close
import QtQuick
import QtQuick.Window
import QtQuick.Shapes
import "i18n.js" as I18n
import QtQuick.Effects

Window {
    id: win
    function tr(text, ...args) { return I18n.tr(Qt.resolvedUrl("locale/"), text, args) }
    visible: true
    visibility: Window.FullScreen
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    color: "transparent"
    title: tr("Switch theme")

    readonly property var args: Qt.application.arguments
    property var themes: []
    property string current: ""
    property int loaded: 0          // decoded preview images
    property bool shown: false
    property bool ready: false      // enable animations only after setup (no expanding on open)
    readonly property real cardH: Math.min(height * 0.42, 460)
    readonly property real wideW: cardH * 1.55
    readonly property real narrowW: cardH * 0.42
    readonly property real slant: cardH * 0.22

    function choose(value) {
        console.log("PLASMARCHY_CHOICE=" + value)
        Qt.quit()
    }

    Component.onCompleted: {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + args[args.length - 1], false)
        xhr.send()
        var m = JSON.parse(xhr.responseText)
        current = m.current
        themes = m.themes
        var idx = themes.findIndex(t => t.slug === current)
        list.currentIndex = idx >= 0 ? idx : 0
        list.positionViewAtIndex(list.currentIndex, ListView.Center)
        fallbackTimer.start()       // if an image fails to load: show anyway
        requestActivate()
    }

    // Dimmed backdrop
    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: "black"
        opacity: 0
        MouseArea { anchors.fill: parent; onClicked: Qt.quit() }
    }

    Item {
        id: stage
        anchors.fill: parent
        opacity: 0
        scale: 0.96
        focus: true

        Keys.onLeftPressed: list.decrementCurrentIndex()
        Keys.onRightPressed: list.incrementCurrentIndex()
        Keys.onReturnPressed: win.choose(win.themes[list.currentIndex].slug)
        Keys.onEnterPressed: win.choose(win.themes[list.currentIndex].slug)
        Keys.onEscapePressed: Qt.quit()
        Keys.onPressed: (e) => {
            if (e.key === Qt.Key_N && win.current !== "") win.choose("__nextbg")
            else if (e.key === Qt.Key_R) win.choose("__restore")
            else if (e.key === Qt.Key_S) win.choose("__studio")
        }

        ListView {
            id: list
            anchors.centerIn: parent
            width: parent.width
            height: win.cardH
            orientation: ListView.Horizontal
            spacing: -win.slant + 14
            model: win.themes
            highlightRangeMode: ListView.StrictlyEnforceRange
            preferredHighlightBegin: (width - win.wideW) / 2
            preferredHighlightEnd: (width + win.wideW) / 2
            highlightMoveDuration: win.ready ? 320 : 0
            boundsBehavior: Flickable.StopAtBounds
            keyNavigationWraps: true
            cacheBuffer: 100000     // create all tiles right away so every image preloads
            interactive: true

            delegate: Item {
                id: card
                required property var modelData
                required property int index
                readonly property bool selected: ListView.isCurrentItem
                width: selected ? win.wideW : win.narrowW
                height: win.cardH
                z: selected ? 2 : 1
                Behavior on width { enabled: win.ready; NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

                Image {
                    id: img
                    anchors.fill: parent
                    source: "file://" + card.modelData.image
                    sourceSize.width: 1200
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: false
                    onStatusChanged: if (status === Image.Ready || status === Image.Error) win.loaded++
                }

                // parallelogram mask
                Item {
                    id: shape
                    anchors.fill: parent
                    layer.enabled: true
                    visible: false
                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            fillColor: "white"
                            strokeWidth: -1
                            startX: win.slant; startY: 0
                            PathLine { x: card.width; y: 0 }
                            PathLine { x: card.width - win.slant; y: card.height }
                            PathLine { x: 0; y: card.height }
                            PathLine { x: win.slant; y: 0 }
                        }
                    }
                }

                MultiEffect {
                    anchors.fill: parent
                    source: img
                    maskEnabled: true
                    maskSource: shape
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                    brightness: card.selected ? 0 : -0.35
                    saturation: card.selected ? 0 : -0.4
                    Behavior on brightness { enabled: win.ready; NumberAnimation { duration: 320 } }
                    Behavior on saturation { enabled: win.ready; NumberAnimation { duration: 320 } }
                }

                // border of the selected theme in its accent color
                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    opacity: card.selected ? 1 : 0
                    Behavior on opacity { enabled: win.ready; NumberAnimation { duration: 220 } }
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: card.modelData.colors[1]
                        strokeWidth: 3
                        joinStyle: ShapePath.RoundJoin
                        startX: win.slant; startY: 1.5
                        PathLine { x: card.width - 1.5; y: 1.5 }
                        PathLine { x: card.width - win.slant; y: card.height - 1.5 }
                        PathLine { x: 1.5; y: card.height - 1.5 }
                        PathLine { x: win.slant; y: 1.5 }
                    }
                }

                // small hint for themes with an animated wallpaper
                Text {
                    visible: !!card.modelData.animation
                    anchors.top: parent.top; anchors.topMargin: 10
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.horizontalCenterOffset: win.slant * 0.45
                    text: String.fromCodePoint(0xF040A)   // play
                    color: "white"
                    opacity: card.selected ? 0.55 : 0.35
                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 13
                    style: Text.Raised; styleColor: Qt.rgba(0, 0, 0, 0.6)
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: card.selected ? win.choose(card.modelData.slug) : list.currentIndex = card.index
                }
            }

            WheelHandler {
                onWheel: (e) => e.angleDelta.y < 0 || e.angleDelta.x < 0 ? list.incrementCurrentIndex() : list.decrementCurrentIndex()
            }
        }

        // name, and a quiet subtitle below the selection
        Column {
            anchors { top: list.bottom; topMargin: 28; horizontalCenter: parent.horizontalCenter }
            spacing: 6
            readonly property var t: win.themes.length ? win.themes[list.currentIndex] : null
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: parent.t ? parent.t.name : ""
                color: "white"
                font.pixelSize: 28
                font.weight: Font.DemiBold
                font.letterSpacing: 1
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: !parent.t ? "" : [parent.t.animation ? tr("animated wallpaper") : "",
                                        parent.t.slug === win.current ? tr("active") : ""].filter(x => x).join("  ·  ")
                color: Qt.rgba(1, 1, 1, 0.5)
                font.pixelSize: 15
                font.letterSpacing: 0.5
            }
        }

        Text {
            anchors { bottom: parent.bottom; bottomMargin: 48; horizontalCenter: parent.horizontalCenter }
            text: "←  →  " + tr("select") + "     ⏎  " + tr("apply") + "     N  " + tr("next wallpaper") + "     S  Theme Studio     R  "
                  + tr("previous look") + "     Esc  " + tr("close")
            color: Qt.rgba(1, 1, 1, 0.55)
            font.pixelSize: 15
        }
    }

    // Fade in only once all previews are decoded (otherwise tiles flash black)
    function show() {
        if (shown) return
        shown = true
        appear.start()
        readyTimer.start()
    }
    onLoadedChanged: if (themes.length && loaded >= themes.length) show()
    Timer { id: fallbackTimer; interval: 500; onTriggered: win.show() }
    Timer { id: readyTimer; interval: 200; onTriggered: win.ready = true }

    ParallelAnimation {
        id: appear
        NumberAnimation { target: backdrop; property: "opacity"; to: 0.72; duration: 220; easing.type: Easing.OutCubic }
        NumberAnimation { target: stage; property: "opacity"; to: 1; duration: 260; easing.type: Easing.OutCubic }
        NumberAnimation { target: stage; property: "scale"; to: 1; duration: 300; easing.type: Easing.OutCubic }
    }
}
