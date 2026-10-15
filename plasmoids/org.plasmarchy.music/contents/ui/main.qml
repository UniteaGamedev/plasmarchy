// Music player for the top bar.
// Built in: Spotify (Premium) through spotify_player - search, liked songs and playlists, no browser needed.
// It also shows and controls any other MPRIS player (YouTube Music or SoundCloud in a browser, VLC, ...).
// Top bar: audio wave, title, previous / play-pause / next. Click: popup. Scroll: previous/next track.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.private.mpris as Mpris
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    readonly property string mono: "JetBrainsMono Nerd Font"
    readonly property string bin: "\"$HOME/.local/bin/plasmarchy\""
    // The player to show: we pick it ourselves instead of Plasma's automatic choice, because an idle Spotify
    // daemon reports "Playing" without any song and would hide the music that really plays. Only players with
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
    // our mpv (YouTube Music) reports no cover: ask for it whenever the song changes
    readonly property bool ownYoutube: !!player && player.identity === "mpv" && !!spotify.youtube && !!spotify.youtube.running
    property string ytCover: ""
    readonly property string coverUrl: player && player.artUrl ? player.artUrl : ownYoutube ? ytCover : ""
    onTitleChanged: if (ownYoutube) run("yt-now")
    onOwnYoutubeChanged: if (ownYoutube) run("yt-now")
    readonly property bool hasPlayer: !!player && player.track !== ""   // an idle player (e.g. Spotify's daemon) doesn't count
    readonly property bool playing: !!player && player.playbackStatus === Mpris.PlaybackStatus.Playing
    readonly property string show: Plasmoid.configuration.show
    readonly property bool visibleInBar: show === "always" || (show === "auto" && hasPlayer)
    // while mpv opens a stream it reports the link as title for a moment: show "Loading …" instead
    readonly property bool loading: !!player && /^(https?|ytdl):|watch\?v=/.test(player.track)
    readonly property string title: !player ? "" : loading ? i18n("Loading …") : player.track || player.identity
    readonly property string artist: !player || loading ? "" : (player.artist || "")
    readonly property string line: artist && title ? artist + " · " + title : title

    // Spotify (spotify_player)
    property var spotify: ({ installed: false, authenticated: false, running: false })
    property var library: []            // liked songs + playlists
    property var results: null          // search results
    property string busy: ""
    property var errors: ({ spotify: "", youtube: "" })   // per source, so Spotify's errors don't show on YouTube
    readonly property string error: errors[youtube ? "youtube" : "spotify"] || ""
    function setError(src, text) { var e = Object.assign({}, errors); e[src] = text; errors = e }

    // player names as people know them: our mpv plays YouTube Music, spotify_player is Spotify
    function niceName(identity) {
        if (identity === "mpv" && spotify.youtube && spotify.youtube.running) return "YouTube Music"
        if (/spotify/i.test(identity)) return "Spotify"
        return identity
    }
    function fmt(us) {
        var s = Math.max(0, Math.floor(us / 1000000))
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }
    function run(args) { exec.connectSource("sh -c 'exec " + bin + " music " + args + "'") }
    readonly property bool youtube: Plasmoid.configuration.source === "youtube"
    // Spotify works reliably only with the user's own (free) Spotify app: the shared one is always rate limited
    readonly property bool spReady: !!spotify.installed && !!spotify.ownApp && !!spotify.authenticated
    readonly property string redirectUri: "http://127.0.0.1:8989/login"
    property var ytResults: []
    function play(item) {
        busy = item.name; setError(item.kind === "yt" ? "youtube" : "spotify", "")
        if (item.kind === "yt") run("yt-play " + item.id)
        else run("play " + item.kind + " " + (item.id || "-"))
    }
    function search(text) {
        busy = "search"; setError(youtube ? "youtube" : "spotify", "")
        run((youtube ? "yt-search64 " : "search64 ") + Qt.btoa(text))
    }

    // source switch (Spotify / YouTube Music) next to the search field
    component SourceButton: PC3.ToolButton {
        required property string source
        required property string label
        checkable: true
        checked: Plasmoid.configuration.source === source
        display: PC3.AbstractButton.IconOnly
        text: label
        onClicked: { Plasmoid.configuration.source = source; checked = Qt.binding(() => Plasmoid.configuration.source === source) }
        PC3.ToolTip { text: parent.label }
    }

    Mpris.Mpris2Model { id: mpris }

    P5Support.DataSource {
        id: exec
        engine: "executable"
        onNewData: (source, data) => {
            disconnectSource(source)
            var out
            try { out = JSON.parse(data.stdout) } catch (e) { out = null }
            if (out && out.error && source.indexOf(" music status") < 0)
                root.setError(source.indexOf(" music yt-") >= 0 ? "youtube" : "spotify", out.error)
            if (source.indexOf(" music status") >= 0) { if (out) root.spotify = out }
            else if (source.indexOf(" music playlists") >= 0) { if (out && out.items) root.library = out.items; root.busy = "" }
            else if (source.indexOf(" music search64 ") >= 0) { if (out && !out.error) root.results = out; root.busy = "" }
            else if (source.indexOf(" music yt-search64 ") >= 0) { if (out && out.items) root.ytResults = out.items; root.busy = "" }
            else if (source.indexOf(" music client-id ") >= 0) { root.busy = ""; root.library = []; root.run("status") }
            else if (source.indexOf(" music yt-now") >= 0) { if (out) root.ytCover = out.image || "" }
            else if (source.indexOf(" music play ") >= 0 || source.indexOf(" music yt-play ") >= 0) { root.busy = ""; root.run("status") }
        }
    }
    // the Spotify library is loaded only when Spotify is the chosen source
    function loadLibrary() {
        if (root.expanded && !youtube && spotify.authenticated && library.length === 0 && busy === "") { busy = "library"; run("playlists") }
    }
    onExpandedChanged: if (root.expanded) { if (player) player.updatePosition(); run("status"); loadLibrary() }
    onSpotifyChanged: loadLibrary()
    onYoutubeChanged: loadLibrary()
    Component.onCompleted: run("status")

    Timer {   // MPRIS only reports the position on request
        interval: 1000; repeat: true
        running: root.playing   // also while closed: the bar is at the right place the moment the popup opens
        onTriggered: root.player.updatePosition()
    }

    Plasmoid.status: visibleInBar ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.HiddenStatus
    preferredRepresentation: compactRepresentation
    toolTipMainText: hasPlayer ? title : i18n("Music")
    toolTipSubText: hasPlayer ? [artist, niceName(player.identity)].filter(x => x).join(" · ") : i18n("Nothing is playing")

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
        readonly property real textWidth: Plasmoid.configuration.showTitle
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
                visible: compact.textWidth > 0
                Layout.preferredWidth: compact.shownWidth
                // same visible gap on both sides: the buttons on the right have their own padding
                Layout.leftMargin: Kirigami.Units.smallSpacing + (Kirigami.Units.gridUnit * 1.6 - Kirigami.Theme.defaultFont.pixelSize * 1.25) / 2
                // without music: a quiet placeholder, so the player keeps its place
                text: root.hasPlayer ? root.line : i18n("Nothing is playing")
                elide: Text.ElideRight
                font.family: root.mono
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                opacity: root.playing ? 0.95 : 0.5
            }
            RowLayout {   // previous / play-pause / next
                spacing: 0
                BarButton { glyph: 0xF04AE; ok: root.hasPlayer && root.player.canGoPrevious; onActivated: root.player.Previous() }
                BarButton { glyph: root.playing ? 0xF03E4 : 0xF040A; ok: root.hasPlayer; onActivated: root.player.PlayPause() }
                BarButton { glyph: 0xF04AD; ok: root.hasPlayer && root.player.canGoNext; onActivated: root.player.Next() }
            }
        }
    }

    // --- Popup ---------------------------------------------------------------------------------
    fullRepresentation: PlasmaExtras.Representation {
        // same size as the system tray popups, and fixed: long titles elide instead of widening the popup
        Layout.preferredWidth: Kirigami.Units.gridUnit * 24
        Layout.maximumWidth: Kirigami.Units.gridUnit * 24
        Layout.preferredHeight: Kirigami.Units.gridUnit * 34   // room for the song list
        Layout.minimumWidth: Kirigami.Units.gridUnit * 24
        Layout.minimumHeight: Kirigami.Units.gridUnit * 20
        collapseMarginsHint: true

        header: PlasmaExtras.PlasmoidHeading {
            // only when more than one player has something loaded (an idle Spotify daemon doesn't count)
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
                            text: container ? root.niceName(container.identity) : ""
                            onClicked: root.chosenIndex = index
                        }
                    }
                }
            }
        }

        ColumnLayout {
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
                                text: root.hasPlayer ? root.niceName(root.player.identity)
                                                     : i18n("Search for a song below to start.") }
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

            Kirigami.Separator { Layout.fillWidth: true }

            // --- Source: Spotify / YouTube Music, two small icons next to the search ---------------------
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                SourceButton { source: "spotify"; label: "Spotify"; icon.name: "spotify" }
                SourceButton { source: "youtube"; label: "YouTube Music"; icon.name: "youtube-music" }
                PlasmaExtras.SearchField {
                    id: searchField
                    Layout.fillWidth: true
                    visible: root.youtube ? (root.spotify.youtube && root.spotify.youtube.installed) : root.spReady
                    placeholderText: root.youtube ? i18n("Search YouTube Music …") : i18n("Search Spotify …")
                    onAccepted: if (text.trim()) root.search(text.trim())
                    onTextChanged: if (text === "") { root.results = null; root.ytResults = [] }
                }
                Item { Layout.fillWidth: true; visible: !searchField.visible }
            }

            // not set up yet: what to do, the command to copy, a terminal, or set it up automatically
            ColumnLayout {
                readonly property bool ytMissing: root.youtube && !(root.spotify.youtube && root.spotify.youtube.installed)
                readonly property bool spMissing: !root.youtube && (!root.spotify.installed || (root.spotify.ownApp && !root.spotify.authenticated))
                readonly property string command: root.youtube ? "sudo pacman -S --needed yt-dlp mpv-mpris"
                                                  : !root.spotify.installed ? "sudo pacman -S --needed spotify-player"
                                                  : "plasmarchy music login"
                visible: ytMissing || spMissing
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Kirigami.Units.largeSpacing
                Item { Layout.fillHeight: true }
                Kirigami.Heading {
                    Layout.fillWidth: true
                    level: 4
                    horizontalAlignment: Text.AlignHCenter
                    text: root.youtube ? i18n("YouTube Music isn't set up yet")
                        : !root.spotify.installed ? i18n("Spotify isn't set up yet") : i18n("Connect your Spotify account")
                }
                PC3.Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    // explains what the buttons below do; the button names are inserted so they always match
                    text: root.youtube ? i18n("Play YouTube Music right here in the top bar. Click “%1” and Plasmarchy installs the two small packages it needs. Prefer doing it yourself? Copy the command below and paste it into a terminal.", i18n("Set up automatically"))
                        : !root.spotify.installed ? i18n("Play Spotify right here in the top bar (Spotify Premium needed). Click “%1” and Plasmarchy installs the player for you. Prefer doing it yourself? Copy the command below and paste it into a terminal.", i18n("Set up automatically"))
                        : i18n("One step left: sign in to Spotify. Click “%1” and confirm the sign in in your browser. Or copy the command below and run it in a terminal yourself.", i18n("Connect Spotify"))
                }
                RowLayout {   // the command, ready to copy
                    Layout.fillWidth: true
                    PC3.TextField {
                        id: commandField
                        Layout.fillWidth: true
                        readOnly: true
                        text: parent.parent.command
                        font.family: root.mono
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    }
                    PC3.ToolButton {
                        icon.name: "edit-copy"
                        onClicked: { commandField.selectAll(); commandField.copy(); commandField.deselect(); copied.visible = true }
                        PC3.ToolTip { text: i18n("Copy") }
                    }
                }
                PC3.Label {
                    id: copied
                    visible: false
                    Layout.alignment: Qt.AlignHCenter
                    text: i18n("Copied. Paste it into the terminal with Ctrl+Shift+V.")
                    font: Kirigami.Theme.smallFont
                    color: Kirigami.Theme.positiveTextColor
                }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    PC3.Button {
                        text: i18n("Open terminal")
                        icon.name: "utilities-terminal"
                        onClicked: { root.expanded = false; exec.connectSource("sh -c 'exec \"$HOME/.local/bin/plasmarchy\" music open-terminal'") }
                    }
                    PC3.Button {
                        text: root.youtube || !root.spotify.installed ? i18n("Set up automatically") : i18n("Connect Spotify")
                        icon.name: "run-build"
                        onClicked: {
                            root.expanded = false
                            exec.connectSource("sh -c 'exec \"$HOME/.local/bin/plasmarchy\" music "
                                + (root.youtube ? "setup youtube" : root.spotify.installed ? "login-terminal" : "setup") + "'")
                        }
                    }
                }
                Item { Layout.fillHeight: true }
            }

            // Spotify: set up your own Spotify app, step by step (Spotify offers no way to create it for you)
            ColumnLayout {
                visible: !root.youtube && root.spotify.installed && !root.spotify.ownApp
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Kirigami.Units.largeSpacing
                Kirigami.Heading {
                    Layout.fillWidth: true
                    level: 4
                    text: i18n("Connect your own Spotify app")
                }
                PC3.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    text: i18n("Spotify only answers reliably with your own free app, because the shared one is used by too many people. This takes about two minutes.")
                }
                // 1. portal
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.largeSpacing
                    PC3.Label { Layout.fillWidth: true; wrapMode: Text.WordWrap
                                text: i18n("1. Open the Spotify developer portal and sign in with your Spotify account.") }
                    PC3.Button {
                        text: i18n("Open portal")
                        icon.name: "internet-web-browser"
                        onClicked: Qt.openUrlExternally("https://developer.spotify.com/dashboard/create")
                    }
                }
                // 2. what to enter
                PC3.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: i18n("2. Create an app with these values, tick “Web API” and save:")
                }
                GridLayout {
                    Layout.fillWidth: true
                    columns: 3
                    columnSpacing: Kirigami.Units.smallSpacing
                    rowSpacing: Kirigami.Units.smallSpacing
                    PC3.Label { text: i18n("App name"); opacity: 0.7; font: Kirigami.Theme.smallFont }
                    PC3.TextField { id: nameField; Layout.fillWidth: true; readOnly: true; text: "Plasmarchy"; font.family: root.mono }
                    PC3.ToolButton { icon.name: "edit-copy"; onClicked: { nameField.selectAll(); nameField.copy(); nameField.deselect(); copiedHint.show() }
                                     PC3.ToolTip { text: i18n("Copy") } }
                    PC3.Label { text: i18n("App description"); opacity: 0.7; font: Kirigami.Theme.smallFont }
                    PC3.TextField { id: descField; Layout.fillWidth: true; readOnly: true; text: "Music in the Plasmarchy top bar"; font.family: root.mono }
                    PC3.ToolButton { icon.name: "edit-copy"; onClicked: { descField.selectAll(); descField.copy(); descField.deselect(); copiedHint.show() }
                                     PC3.ToolTip { text: i18n("Copy") } }
                    PC3.Label { text: "Redirect URI"; opacity: 0.7; font: Kirigami.Theme.smallFont }
                    PC3.TextField { id: uriField; Layout.fillWidth: true; readOnly: true; text: root.redirectUri; font.family: root.mono }
                    PC3.ToolButton { icon.name: "edit-copy"; onClicked: { uriField.selectAll(); uriField.copy(); uriField.deselect(); copiedHint.show() }
                                     PC3.ToolTip { text: i18n("Copy") } }
                }
                PC3.Label {
                    id: copiedHint
                    function show() { visible = true; hideHint.restart() }
                    visible: false
                    text: i18n("Copied")
                    font: Kirigami.Theme.smallFont
                    color: Kirigami.Theme.positiveTextColor
                    Timer { id: hideHint; interval: 2000; onTriggered: copiedHint.visible = false }
                }
                // 3. client id
                PC3.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: i18n("3. Open the new app, copy its Client ID and paste it here:")
                }
                RowLayout {
                    Layout.fillWidth: true
                    PC3.TextField {
                        id: clientIdField
                        Layout.fillWidth: true
                        placeholderText: "Client ID"
                        font.family: root.mono
                        readonly property string clean: text.trim().toLowerCase()
                        readonly property bool valid: /^[0-9a-f]{32}$/.test(clean)
                        onAccepted: if (valid) connectButton.clicked()
                    }
                    PC3.Button {
                        id: connectButton
                        text: i18n("Connect")
                        icon.name: "network-connect"
                        enabled: clientIdField.valid && root.busy !== "client-id"
                        onClicked: { root.busy = "client-id"; root.setError("spotify", ""); root.run("client-id " + clientIdField.clean) }
                    }
                }
                PC3.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    visible: clientIdField.text.trim() !== "" && !clientIdField.valid
                    text: i18n("That doesn't look like a Client ID (32 characters, 0-9 and a-f).")
                    font: Kirigami.Theme.smallFont
                    color: Kirigami.Theme.negativeTextColor
                }
                RowLayout {
                    visible: root.busy === "client-id"
                    spacing: Kirigami.Units.smallSpacing
                    PC3.BusyIndicator { running: parent.visible; implicitWidth: Kirigami.Units.iconSizes.small; implicitHeight: implicitWidth }
                    PC3.Label { Layout.fillWidth: true; wrapMode: Text.WordWrap
                                text: i18n("Confirm the connection to “Plasmarchy” in your browser …") }
                }
                PC3.Label {
                    visible: root.error !== ""
                    text: root.error
                    color: Kirigami.Theme.negativeTextColor
                    wrapMode: Text.WordWrap; Layout.fillWidth: true
                    font: Kirigami.Theme.smallFont
                }
                Item { Layout.fillHeight: true }
            }

            // search and library
            ColumnLayout {
                visible: root.youtube ? (root.spotify.youtube && root.spotify.youtube.installed) : root.spReady
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Kirigami.Units.largeSpacing
                PC3.Label {
                    visible: root.error !== ""
                    text: root.error
                    color: Kirigami.Theme.negativeTextColor
                    wrapMode: Text.WordWrap; Layout.fillWidth: true
                    font: Kirigami.Theme.smallFont
                }
                PC3.Label {
                    visible: root.youtube && root.ytResults.length === 0 && root.busy === ""
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    opacity: 0.55
                    font: Kirigami.Theme.smallFont
                    text: i18n("Search for a song. It starts a radio with similar music.")
                }
                PC3.ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    ListView {
                        id: list
                        clip: true
                        // YouTube results, Spotify library, or Spotify search results grouped by type
                        model: root.youtube ? root.ytResults
                             : root.results === null ? root.library
                             : [].concat(root.results.tracks || [], root.results.playlists || [],
                                         root.results.albums || [], root.results.artists || [])
                        section.property: !root.youtube && root.results !== null ? "kind" : ""
                        section.delegate: PC3.Label {
                            required property string section
                            text: section === "track" ? i18n("Songs") : section === "playlist" ? i18n("Playlists")
                                : section === "album" ? i18n("Albums") : i18n("Artists")
                            font.bold: true; opacity: 0.6
                            topPadding: Kirigami.Units.smallSpacing
                        }
                        delegate: PC3.ItemDelegate {
                            required property var modelData
                            width: ListView.view.width
                            topPadding: Kirigami.Units.smallSpacing; bottomPadding: Kirigami.Units.smallSpacing
                            onClicked: root.play(modelData)
                            contentItem: RowLayout {
                                spacing: Kirigami.Units.largeSpacing
                                Rectangle {
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 2.2
                                    Layout.preferredHeight: Layout.preferredWidth
                                    radius: modelData.kind === "artist" ? width / 2 : 3
                                    color: Qt.alpha(Kirigami.Theme.highlightColor, 0.15)
                                    clip: true
                                    Image { anchors.fill: parent; source: modelData.image || ""; fillMode: Image.PreserveAspectCrop
                                            asynchronous: true; visible: status === Image.Ready }
                                    PC3.Label { anchors.centerIn: parent; visible: !modelData.image
                                                text: String.fromCodePoint(modelData.kind === "liked" ? 0xF02D1 : 0xF0CB8)
                                                font.family: root.mono; color: Kirigami.Theme.highlightColor }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    PC3.Label { Layout.fillWidth: true; text: modelData.name; elide: Text.ElideRight }
                                    PC3.Label { Layout.fillWidth: true; visible: text !== ""; text: modelData.sub || ""
                                                elide: Text.ElideRight; opacity: 0.55; font: Kirigami.Theme.smallFont }
                                }
                                PC3.BusyIndicator {
                                    visible: root.busy === modelData.name
                                    running: visible
                                    implicitWidth: Kirigami.Units.iconSizes.small; implicitHeight: implicitWidth
                                }
                            }
                        }
                        PC3.BusyIndicator {
                            anchors.centerIn: parent
                            visible: (root.busy === "library" || root.busy === "search") && list.count === 0
                            running: visible
                        }
                    }
                }
            }
        }
    }
}
