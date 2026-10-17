// Music player for the top bar: shows and controls whatever plays, in any app (MPRIS: Spotify, a browser,
// VLC, ...). The music itself is started where the user likes, the player doesn't play anything on its own.
// Top bar: audio wave, title, previous / play-pause / next. Click: popup. Scroll: previous/next track.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.private.mpris as Mpris
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    readonly property string mono: "JetBrainsMono Nerd Font"
    // The player to show: we pick it ourselves instead of Plasma's automatic choice, because an idle player can
    // report "Playing" without any song and would hide the music that really plays. Only players with
    // a song count; a playing one wins over a paused one; a tab the user clicked wins over both.
    property int playersRev: 0
    property int chosenIndex: -1
    Instantiator {
        id: allPlayers
        model: mpris
        delegate: Item {
            required property var container
            required property bool isMultiplexer
            required property int index
            readonly property string track: container ? container.track : ""
            readonly property int status: container ? container.playbackStatus : 0
            onTrackChanged: root.playersRev++
            onStatusChanged: root.playersRev++
        }
        onObjectAdded: root.playersRev++
        onObjectRemoved: root.playersRev++
    }
    readonly property var pick: {
        playersRev
        var best = null, bestIndex = -1, bestScore = -1
        for (var i = 0; i < allPlayers.count; i++) {
            var o = allPlayers.objectAt(i)
            if (!o || o.isMultiplexer || !o.container || o.track === "") continue
            var score = (o.status === Mpris.PlaybackStatus.Playing ? 2 : 1) + (i === chosenIndex ? 4 : 0)
            if (score > bestScore) { best = o.container; bestIndex = i; bestScore = score }
        }
        var withSong = 0
        for (var j = 0; j < allPlayers.count; j++) {
            var p = allPlayers.objectAt(j)
            if (p && !p.isMultiplexer && p.container && p.track !== "") withSong++
        }
        return { player: best, index: bestIndex, count: withSong }
    }
    readonly property var player: pick.player
    readonly property string coverUrl: player && player.artUrl ? player.artUrl : ""
    readonly property bool hasPlayer: !!player && player.track !== ""   // an idle player without a song doesn't count
    readonly property bool playing: !!player && player.playbackStatus === Mpris.PlaybackStatus.Playing
    readonly property string show: Plasmoid.configuration.show
    readonly property bool visibleInBar: show === "always" || (show === "auto" && hasPlayer)
    // a player opening a stream (e.g. mpv) reports the link as title for a moment: show "Loading …" instead
    readonly property bool loading: !!player && /^(https?|ytdl):|watch\?v=/.test(player.track)
    readonly property string title: !player ? "" : loading ? i18n("Loading …") : player.track || player.identity
    readonly property string artist: !player || loading ? "" : (player.artist || "")
    readonly property string line: artist && title ? artist + " · " + title : title

    function fmt(us) {
        var s = Math.max(0, Math.floor(us / 1000000))
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }

    Mpris.Mpris2Model { id: mpris }

    onExpandedChanged: if (root.expanded && player) player.updatePosition()

    Timer {   // MPRIS only reports the position on request
        interval: 1000; repeat: true
        running: root.playing   // also while closed: the bar is at the right place the moment the popup opens
        onTriggered: root.player.updatePosition()
    }

    Plasmoid.status: visibleInBar ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.HiddenStatus
    preferredRepresentation: compactRepresentation
    toolTipMainText: hasPlayer ? title : i18n("Music")
    toolTipSubText: hasPlayer ? [artist, player.identity].filter(x => x).join(" · ") : i18n("Nothing is playing")

    // --- Top bar ---------------------------------------------------------------------------------
    // a control in the top bar: a real button with a hover background, sized for the bar
    component BarButton: MouseArea {
        id: barButton
        property int glyph
        property bool ok: true
        signal activated()
        implicitWidth: Kirigami.Units.gridUnit * 1.6
        implicitHeight: implicitWidth
        Layout.alignment: Qt.AlignVCenter
        hoverEnabled: true
        enabled: ok
        onClicked: activated()
        Rectangle {
            anchors.fill: parent
            radius: Kirigami.Units.cornerRadius
            color: Kirigami.Theme.highlightColor
            opacity: barButton.containsMouse ? 0.2 : 0
        }
        PC3.Label {
            anchors.centerIn: parent
            text: String.fromCodePoint(barButton.glyph)
            font.family: root.mono
            font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.25
            opacity: !barButton.ok ? 0.3 : barButton.containsMouse ? 1 : 0.85
            color: barButton.containsMouse ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
        }
    }

    compactRepresentation: MouseArea {
        id: compact
        // without a song only the wave stays in the bar (click opens the popup)
        readonly property real textWidth: Plasmoid.configuration.showTitle && root.hasPlayer
            ? Math.min(label.implicitWidth, Kirigami.Units.gridUnit * Plasmoid.configuration.maxTitleWidth) : 0
        // a new title glides to its width instead of making the top bar jump
        property real shownWidth: textWidth
        Behavior on shownWidth { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
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
            // audio wave: bars bounce while music plays, a flat line otherwise
            Timer { id: wave; property int step: 0; interval: 166; repeat: true; running: root.playing; onTriggered: step++ }
            Row {
                spacing: 2
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredHeight: 16
                Repeater {
                    model: 4
                    delegate: Rectangle {
                        required property int index
                        width: 2; radius: 1
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.playing ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
                        opacity: root.hasPlayer ? 0.9 : 0.4
                        // a level meter that jumps 6 times a second: a smooth 60 fps animation would make
                        // Plasma redraw the whole top bar all the time (that alone cost a third of a CPU core)
                        height: root.playing ? 3 + Math.round(Math.abs(Math.sin(wave.step * (1.3 + index * 0.7) + index * 2)) * 10) : 3
                    }
                }
            }
            PC3.Label {
                id: label
                visible: compact.shownWidth > 0   // stays while it glides out
                Layout.preferredWidth: compact.shownWidth
                // same visible gap on both sides: the buttons on the right have their own padding
                Layout.leftMargin: Kirigami.Units.smallSpacing + (Kirigami.Units.gridUnit * 1.6 - Kirigami.Theme.defaultFont.pixelSize * 1.25) / 2
                text: root.hasPlayer ? root.line : ""
                elide: Text.ElideRight
                font.family: root.mono
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                opacity: root.playing ? 0.95 : 0.5
            }
            RowLayout {   // previous / play-pause / next
                visible: root.hasPlayer
                spacing: 0
                BarButton { glyph: 0xF04AE; ok: root.hasPlayer && root.player.canGoPrevious; onActivated: root.player.Previous() }
                BarButton { glyph: root.playing ? 0xF03E4 : 0xF040A; ok: root.hasPlayer; onActivated: root.player.PlayPause() }
                BarButton { glyph: 0xF04AD; ok: root.hasPlayer && root.player.canGoNext; onActivated: root.player.Next() }
            }
        }
    }

    // --- Popup ---------------------------------------------------------------------------------
    fullRepresentation: PlasmaExtras.Representation {
        id: popup
        // as wide as the system tray popups, and fixed: long titles elide instead of widening the popup;
        // as high as what it shows
        Layout.preferredWidth: Kirigami.Units.gridUnit * 24
        Layout.maximumWidth: Kirigami.Units.gridUnit * 24
        Layout.minimumWidth: Kirigami.Units.gridUnit * 24
        Layout.preferredHeight: content.implicitHeight + content.anchors.margins * 2
                                + (popup.header.visible ? popup.header.implicitHeight : 0)
        Layout.minimumHeight: Layout.preferredHeight
        Layout.maximumHeight: Layout.preferredHeight
        collapseMarginsHint: true

        header: PlasmaExtras.PlasmoidHeading {
            // only when more than one player has something loaded (an idle player doesn't count)
            visible: root.pick.count > 1
            RowLayout {
                anchors.fill: parent
                PC3.TabBar {
                    Layout.fillWidth: true
                    currentIndex: Math.max(0, root.pick.index)
                    Repeater {
                        id: players
                        model: mpris
                        delegate: PC3.TabButton {
                            required property var container
                            required property bool isMultiplexer
                            required property int index
                            readonly property bool shown: !isMultiplexer && !!container && container.track !== ""
                            visible: shown
                            width: shown ? implicitWidth : 0
                            text: container ? container.identity : ""
                            onClicked: root.chosenIndex = index
                        }
                    }
                }
            }
        }

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing * 1.5
            spacing: Kirigami.Units.largeSpacing * 1.5

            // now playing (a placeholder while nothing plays): cover and text share one fixed height,
            // title at the top, controls at the bottom
            RowLayout {
                id: nowPlaying
                readonly property real size: Kirigami.Units.gridUnit * 6.5
                Layout.fillWidth: true
                Layout.preferredHeight: size
                Layout.minimumHeight: size
                Layout.maximumHeight: size
                spacing: Kirigami.Units.gridUnit * 1.2   // a clear gap between cover and text
                Rectangle {
                    Layout.preferredWidth: nowPlaying.size
                    Layout.preferredHeight: nowPlaying.size
                    radius: Kirigami.Units.cornerRadius * 1.5
                    color: Qt.alpha(Kirigami.Theme.highlightColor, 0.15)
                    clip: true
                    Image {
                        id: cover
                        anchors.fill: parent
                        source: root.hasPlayer ? root.coverUrl : ""
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
                        opacity: root.hasPlayer ? 1 : 0.5
                    }
                }
                ColumnLayout {
                    id: info
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Kirigami.Units.smallSpacing
                    Kirigami.Heading { Layout.fillWidth: true; level: 3; elide: Text.ElideRight
                                       text: root.hasPlayer ? root.title : i18n("Nothing is playing")
                                       opacity: root.hasPlayer ? 1 : 0.6 }
                    PC3.Label { Layout.fillWidth: true; visible: text !== ""; text: root.artist; elide: Text.ElideRight
                                color: Kirigami.Theme.highlightColor }
                    PC3.Label { Layout.fillWidth: true; elide: Text.ElideRight; opacity: 0.45; font: Kirigami.Theme.smallFont
                                wrapMode: root.hasPlayer ? Text.NoWrap : Text.WordWrap; maximumLineCount: 2   // the hint may wrap
                                text: root.hasPlayer ? root.player.identity
                                                     : i18n("Start music in any app. It shows up here.") }
                    Item { Layout.fillHeight: true }
                    RowLayout {
                        Layout.leftMargin: -Kirigami.Units.smallSpacing   // the buttons' own padding lines them up with the text
                        spacing: Kirigami.Units.smallSpacing
                        PC3.ToolButton { icon.name: "media-playlist-shuffle"; checkable: true
                                         checked: root.hasPlayer && root.player.shuffle
                                         enabled: root.hasPlayer && root.player.canControl
                                         onClicked: root.player.shuffle = !root.player.shuffle }
                        PC3.ToolButton { icon.name: "media-skip-backward"; enabled: root.hasPlayer && root.player.canGoPrevious
                                         onClicked: root.player.Previous() }
                        PC3.ToolButton { icon.name: root.playing ? "media-playback-pause" : "media-playback-start"
                                         enabled: root.hasPlayer
                                         onClicked: root.player.PlayPause() }
                        PC3.ToolButton { icon.name: "media-skip-forward"; enabled: root.hasPlayer && root.player.canGoNext
                                         onClicked: root.player.Next() }
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
                    from: 0; to: root.player ? root.player.length : 1
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
        }
    }
}
