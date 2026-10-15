// Music player for the top bar: shows what's playing in any MPRIS player (Spotify, YouTube Music or
// SoundCloud in a browser, VLC, ...). Click: popup with cover, progress and controls. Middle click: play/pause.
// Scroll: previous/next track. Hidden while nothing is running (setting "show").
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.private.mpris as Mpris
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    readonly property string mono: "JetBrainsMono Nerd Font"
    readonly property var player: mpris.currentPlayer
    readonly property bool hasPlayer: !!player && (player.track !== "" || player.identity !== "")
    readonly property bool playing: !!player && player.playbackStatus === Mpris.PlaybackStatus.Playing
    readonly property string show: Plasmoid.configuration.show
    readonly property bool visibleInBar: show === "always" || (show === "auto" && hasPlayer)
    readonly property string title: !player ? "" : player.track || player.identity
    readonly property string artist: !player ? "" : (player.artist || "")
    readonly property string line: artist && title ? artist + " – " + title : title

    function fmt(us) {
        var s = Math.max(0, Math.floor(us / 1000000))
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }

    Mpris.Mpris2Model { id: mpris }

    Timer {   // MPRIS only reports the position on request
        interval: 1000; repeat: true
        running: root.expanded && root.playing
        onTriggered: root.player.updatePosition()
    }

    Plasmoid.status: visibleInBar ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.HiddenStatus
    preferredRepresentation: compactRepresentation
    toolTipMainText: hasPlayer ? title : i18n("Music")
    toolTipSubText: hasPlayer ? [artist, player.identity].filter(x => x).join(" · ") : i18n("Nothing is playing")

    compactRepresentation: MouseArea {
        id: compact
        readonly property real textWidth: Plasmoid.configuration.showTitle && root.hasPlayer
            ? Math.min(label.implicitWidth, Kirigami.Units.gridUnit * Plasmoid.configuration.maxTitleWidth) : 0
        visible: root.visibleInBar
        Layout.minimumWidth: visible ? row.implicitWidth + Kirigami.Units.smallSpacing * 2 : 0
        Layout.preferredWidth: Layout.minimumWidth
        Layout.maximumWidth: Layout.minimumWidth
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        hoverEnabled: true
        onClicked: (mouse) => {
            if (mouse.button === Qt.MiddleButton) { if (root.player) root.player.PlayPause() }
            else root.expanded = !root.expanded
        }
        onWheel: (wheel) => {
            if (!root.player) return
            if (wheel.angleDelta.y > 0 && root.player.canGoPrevious) root.player.Previous()
            else if (wheel.angleDelta.y < 0 && root.player.canGoNext) root.player.Next()
        }
        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing
            PC3.Label {
                text: root.playing ? String.fromCodePoint(0xF075A) : String.fromCodePoint(0xF03E4)   // note / pause
                font.family: root.mono
                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.05
                color: root.playing ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
                opacity: root.hasPlayer ? 1 : 0.5
            }
            PC3.Label {
                id: label
                visible: compact.textWidth > 0
                Layout.preferredWidth: compact.textWidth
                text: root.line
                elide: Text.ElideRight
                font.family: root.mono
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                opacity: root.playing ? 0.95 : 0.6
            }
        }
    }

    fullRepresentation: PlasmaExtras.Representation {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 24    // same width as the system tray popups
        Layout.preferredHeight: content.implicitHeight + Kirigami.Units.largeSpacing * 2
                                + (heading.visible ? heading.implicitHeight : 0)
        Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        Layout.minimumHeight: Layout.preferredHeight
        collapseMarginsHint: true

        header: PlasmaExtras.PlasmoidHeading {
            id: heading
            visible: players.count > 2   // the model always contains the automatic "multiplexer" entry
            RowLayout {
                anchors.fill: parent
                PC3.TabBar {
                    id: tabs
                    Layout.fillWidth: true
                    currentIndex: Math.max(0, mpris.currentIndex - 1)
                    Repeater {
                        id: players
                        model: mpris
                        delegate: PC3.TabButton {
                            required property string identity
                            required property bool isMultiplexer
                            required property int index
                            visible: !isMultiplexer
                            width: isMultiplexer ? 0 : implicitWidth
                            text: identity
                            onClicked: mpris.currentIndex = index
                        }
                    }
                }
            }
        }

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            PlasmaExtras.PlaceholderMessage {
                visible: !root.hasPlayer
                Layout.fillWidth: true
                iconName: "media-playback-start"
                text: i18n("Nothing is playing")
                explanation: i18n("Start Spotify, or YouTube Music or SoundCloud in your browser.")
            }

            RowLayout {
                visible: root.hasPlayer
                spacing: Kirigami.Units.largeSpacing
                Rectangle {   // cover
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 6
                    Layout.preferredHeight: Layout.preferredWidth
                    radius: Kirigami.Units.cornerRadius
                    color: Qt.alpha(Kirigami.Theme.highlightColor, 0.15)
                    clip: true
                    Image {
                        id: cover
                        anchors.fill: parent
                        source: root.player ? root.player.artUrl : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: status === Image.Ready
                    }
                    PC3.Label {
                        anchors.centerIn: parent
                        visible: cover.status !== Image.Ready
                        text: String.fromCodePoint(0xF075A)
                        font.family: root.mono
                        font.pixelSize: Kirigami.Units.gridUnit * 2
                        color: Kirigami.Theme.highlightColor
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Kirigami.Heading {
                        Layout.fillWidth: true
                        level: 4
                        text: root.title
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                    PC3.Label {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: root.artist
                        elide: Text.ElideRight
                        color: Kirigami.Theme.highlightColor
                    }
                    PC3.Label {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: root.player ? root.player.album : ""
                        elide: Text.ElideRight
                        opacity: 0.6
                        font: Kirigami.Theme.smallFont
                    }
                    PC3.Label {
                        text: root.player ? root.player.identity : ""
                        opacity: 0.45
                        font: Kirigami.Theme.smallFont
                    }
                }
            }

            ColumnLayout {   // progress
                visible: root.hasPlayer && root.player.length > 0
                Layout.fillWidth: true
                spacing: 0
                PC3.Slider {
                    id: progress
                    Layout.fillWidth: true
                    from: 0
                    to: root.player ? root.player.length : 1
                    value: root.player ? root.player.position : 0
                    enabled: root.player && root.player.canSeek
                    onMoved: root.player.position = value
                }
                RowLayout {
                    PC3.Label { text: root.fmt(progress.value); font: Kirigami.Theme.smallFont; opacity: 0.6 }
                    Item { Layout.fillWidth: true }
                    PC3.Label { text: root.player ? root.fmt(root.player.length) : ""; font: Kirigami.Theme.smallFont; opacity: 0.6 }
                }
            }

            RowLayout {   // controls
                visible: root.hasPlayer
                Layout.alignment: Qt.AlignHCenter
                spacing: Kirigami.Units.largeSpacing
                PC3.ToolButton {
                    icon.name: "media-playlist-shuffle"
                    checkable: true
                    checked: root.player && root.player.shuffle
                    visible: root.player && root.player.canControl
                    onClicked: root.player.shuffle = !root.player.shuffle
                    PC3.ToolTip { text: i18n("Shuffle") }
                }
                PC3.ToolButton {
                    icon.name: "media-skip-backward"
                    enabled: root.player && root.player.canGoPrevious
                    onClicked: root.player.Previous()
                }
                PC3.Button {
                    icon.name: root.playing ? "media-playback-pause" : "media-playback-start"
                    icon.width: Kirigami.Units.iconSizes.medium
                    icon.height: Kirigami.Units.iconSizes.medium
                    enabled: root.player && (root.playing ? root.player.canPause : root.player.canPlay)
                    onClicked: root.player.PlayPause()
                }
                PC3.ToolButton {
                    icon.name: "media-skip-forward"
                    enabled: root.player && root.player.canGoNext
                    onClicked: root.player.Next()
                }
                PC3.ToolButton {
                    icon.name: "go-up"
                    visible: root.player && root.player.canRaise
                    onClicked: { root.player.Raise(); root.expanded = false }
                    PC3.ToolTip { text: i18n("Show the player") }
                }
            }
        }
    }
}
