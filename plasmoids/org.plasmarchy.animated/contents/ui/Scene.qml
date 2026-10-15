// The animated scene itself - independent of Plasma, so it can also be rendered offscreen for previews.
// Effects: "aurora" (soft drifting color clouds), "particles" (rising glow dots, logo sparkling from particles),
// "rain" (digital rain), "logo" (the ASCII logo assembling itself like in the screensaver).
// Except for "logo", they draw the branding logo in the accent color in the middle (unless showLogo is off).
import QtQuick
import QtQuick.Effects

Item {
    id: scene
    property string effect: "aurora"
    property color background: "#111c18"
    property color darkBackground: "#090f0d"
    property color foreground: "#C1C497"
    property color accent: "#509475"
    property var colorList: ["#2DD5B7", "#D2689C", "#549e6a", "#8CD3CB"]
    property url logo: ""
    property bool showLogo: true
    property real speed: 1.0
    property bool running: true
    property string logoAscii: ""        // the screensaver's ASCII logo (effect "logo")
    property bool logoAnimated: false    // show the logo animated like the screensaver on every effect

    readonly property real unit: Math.min(width, height) / 100

    // Performance: every effect is a GPU shader, the CPU only advances this clock. Each effect gets just as many
    // frames as it needs to look smooth (the slow aurora 15, the rain its classic 15, the particles 20, the logo
    // 25 while it builds up and 8 while it stands) - every frame Plasma and KWin don't have to draw saves CPU.
    property real clock: 0               // seconds (wraps after two hours to keep the shaders precise)
    readonly property int frameInterval: {
        var ms = effect === "particles" ? 50 : effect === "logo" ? 125 : 66
        return ascii.active ? Math.min(ms, ascii.moving ? 40 : 125) : ms
    }
    Timer {
        interval: scene.frameInterval; repeat: true
        running: scene.running
        onTriggered: scene.clock = (scene.clock + interval / 1000 * scene.speed) % 7200
    }
    function col(i) { return colorList.length ? colorList[i % colorList.length] : accent }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: scene.background }
            GradientStop { position: 1; color: scene.darkBackground }
        }
    }

    // --- Aurora: radial color clouds wandering slowly -----------------------------------------------
    ShaderEffect {
        anchors.fill: parent
        visible: scene.effect === "aurora"
        readonly property size size: Qt.size(width, height)
        readonly property real clock: scene.clock
        readonly property color c0: scene.accent
        readonly property color c1: scene.col(0)
        readonly property color c2: scene.col(1)
        readonly property color c3: scene.col(2)
        readonly property color c4: scene.col(3)
        fragmentShader: "../shaders/aurora.frag.qsb"
    }

    // --- Particles: glow dots rising, plus the logo sparkling ---------------------------------------
    Rectangle {   // warm glow along the bottom edge the particles rise from
        visible: scene.effect === "particles"
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        height: parent.height * 0.45
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.alpha(scene.accent, 0) }
            GradientStop { position: 1; color: Qt.alpha(scene.accent, 0.22) }
        }
        opacity: 0.85
    }

    // rising glow dots
    ShaderEffect {
        anchors.fill: parent
        visible: scene.effect === "particles"
        readonly property size size: Qt.size(width, height)
        readonly property real clock: scene.clock
        readonly property real lanes: 36
        readonly property color accent: scene.accent
        readonly property color second: scene.col(0)
        fragmentShader: "../shaders/particles.frag.qsb"
    }
    // the logo sparkles: dots twinkling where the logo is
    ShaderEffect {
        x: logoBox.x; y: logoBox.y; width: logoBox.width; height: logoBox.height
        visible: scene.effect === "particles" && scene.showLogo && logoImage.status === Image.Ready
        readonly property size size: Qt.size(width, height)
        readonly property size grid: ascii.lines.length ? Qt.size(ascii.cols, ascii.lines.length) : Qt.size(40, 8)
        readonly property real clock: scene.clock
        readonly property real unit: scene.unit
        readonly property real density: ascii.cells.length ? Math.min(1, 90 / ascii.cells.length) : 0.3
        readonly property color color: Qt.tint(scene.accent, Qt.rgba(1, 1, 1, 0.35))
        readonly property var logo: logoImage
        fragmentShader: "../shaders/sparkle.frag.qsb"
    }

    // --- Rain: digital rain like in The Matrix --------------------------------------------------
    // Computed entirely on the GPU (shaders/rain.frag) in full resolution: the CPU only advances the clock
    // 15 times a second.
    Item {
        id: matrix
        visible: scene.effect === "rain"
        anchors.fill: parent
        readonly property real cell: Math.round(Math.max(16, scene.unit * 1.7))
        // the characters, drawn once into an 8 x 8 texture with one glyph per cell (no scaling, crisp)
        readonly property string glyphs: "ｦｱｳｴｵｶｷｹｺｻｼｽｾｿﾀﾂﾃﾅﾆﾇﾈﾊﾋﾎﾏﾐﾑﾒﾓﾔﾕﾗﾘﾜ012345789Z:・.\"=*+-<>¦｜ｸｹﾁﾄﾍﾙﾚﾛ"
        Grid {
            id: atlasItem
            columns: 8
            visible: matrix.visible
            Repeater {
                model: 64
                Text {
                    required property int index
                    width: matrix.cell; height: matrix.cell
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    text: matrix.glyphs[index % matrix.glyphs.length]
                    font.family: "Noto Sans CJK JP"
                    font.pixelSize: Math.round(matrix.cell * 0.9)
                    font.weight: Font.Medium
                    renderType: Text.NativeRendering
                    color: "white"
                }
            }
        }
        ShaderEffectSource {
            id: atlas
            sourceItem: atlasItem
            hideSource: true
            live: false
            smooth: true
            textureSize: Qt.size(matrix.cell * 8, matrix.cell * 8)
            width: 0; height: 0
        }
        ShaderEffect {
            anchors.fill: parent
            readonly property size size: Qt.size(width, height)
            readonly property real cell: matrix.cell
            readonly property real tick: Math.floor(scene.clock * 15)
            readonly property color bg: scene.darkBackground
            readonly property color trail: scene.accent
            readonly property color head: Qt.tint(scene.foreground, Qt.rgba(1, 1, 1, 0.55))
            readonly property var atlas: atlas
            fragmentShader: "../shaders/rain.frag.qsb"
        }
    }

    // --- Logo animation: the ASCII logo builds itself up like the screensaver's text effects ------
    Item {
        id: ascii
        anchors.fill: parent
        readonly property bool active: scene.effect === "logo" || (scene.logoAnimated && scene.showLogo)
        visible: active
        readonly property var lines: scene.logoAscii.split("\n").filter((l, i, a) => l.trim() !== "" || (i > 0 && i < a.length - 1))
        readonly property int cols: Math.max(1, ...lines.map(l => l.length))
        readonly property real cw: Math.min(scene.width * 0.6 / cols, scene.height * 0.5 / Math.max(1, lines.length) / 2)
        readonly property real ch: cw * 2
        readonly property real ox: (width - cols * cw) / 2
        readonly property real oy: (height - lines.length * ch) / 2
        readonly property string noise: "ｱｲｳｴｵｶｷｸ01<>{}[]=+*#%&$@?!/\\|"
        readonly property var modes: ["decrypt", "scatter", "fall", "sweep"]
        property int mode: 0
        property real t: 0            // 0..1 build-up, then hold, then 1..2 dissolve
        readonly property var cells: {
            var out = []
            for (var r = 0; r < lines.length; r++)
                for (var c = 0; c < lines[r].length; c++)
                    if (lines[r][c] !== " ")
                        out.push({ ch: lines[r][c], c: c, r: r, seed: Math.random(), sx: Math.random(), sy: Math.random() })
            return out
        }
        function ease(x) { x = Math.max(0, Math.min(1, x)); return 1 - Math.pow(1 - x, 3) }

        // one cycle: build up 4.2 s, stand 9 s, dissolve 1.8 s - then the next mode. While the logo stands, only
        // the color wave moves, and only 8 times a second.
        readonly property real cycle: 15
        readonly property real phase: scene.clock % cycle
        readonly property real shimmer: scene.clock / 6 % 1    // the color wave, one pass every 6 s
        onPhaseChanged: {
            var p = phase
            var newT = p < 4.2 ? p / 4.2 : p < 13.2 ? 1 : 1 + Math.pow((p - 13.2) / 1.8, 2)
            if (newT !== t) t = newT
        }
        readonly property int cycleNo: Math.floor(scene.clock / cycle)
        onCycleNoChanged: mode = (mode + 1) % modes.length
        readonly property bool moving: phase < 4.3 || phase > 13.1

        // the characters are drawn white, this shader colors them (so the color wave costs no CPU)
        layer.enabled: active
        layer.effect: ShaderEffect {
            readonly property size size: Qt.size(ascii.width, ascii.height)
            readonly property point origin: Qt.point(ascii.ox, ascii.oy)
            readonly property size cellSize: Qt.size(ascii.cw, ascii.ch)
            readonly property real cols: ascii.cols
            readonly property real shimmer: ascii.shimmer
            readonly property color fg: scene.foreground
            readonly property color accent: scene.accent
            readonly property color c0: scene.col(0)
            readonly property color c1: scene.col(1)
            readonly property color c2: scene.col(2)
            readonly property color c3: scene.col(3)
            fragmentShader: "../shaders/logo.frag.qsb"
        }

        Repeater {
            model: ascii.active ? ascii.cells : []
            delegate: Text {
                required property var modelData
                readonly property var m: modelData
                readonly property string kind: ascii.modes[ascii.mode]
                // per-cell progress: staggered by position / chance, depending on the mode
                readonly property real delay: kind === "fall" ? m.c / ascii.cols * 0.55 + m.seed * 0.1
                                            : kind === "sweep" ? m.c / ascii.cols * 0.7
                                            : m.seed * 0.6
                readonly property real p: ascii.t <= 1 ? ascii.ease((ascii.t - delay) / 0.4) : 1
                readonly property real out: ascii.t > 1 ? ascii.ease((ascii.t - 1 - m.seed * 0.5) / 0.5) : 0
                readonly property real hx: ascii.ox + m.c * ascii.cw
                readonly property real hy: ascii.oy + m.r * ascii.ch
                x: kind === "scatter" ? m.sx * scene.width + (hx - m.sx * scene.width) * p : hx
                y: kind === "scatter" ? m.sy * scene.height + (hy - m.sy * scene.height) * p
                 : kind === "fall" ? -ascii.ch + (hy + ascii.ch) * p + out * (scene.height - hy) * 0.15
                 : hy
                width: ascii.cw; height: ascii.ch
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: ascii.ch * 0.95
                // decrypt: random glyphs until the cell settles
                text: kind === "decrypt" && p < 1 && p > 0 ? ascii.noise[Math.floor((m.seed * 97 + ascii.t * 60)) % ascii.noise.length] : m.ch
                opacity: (kind === "decrypt" || kind === "sweep" ? (p > 0 ? 1 : 0) : Math.min(1, p * 1.5)) * (1 - out)
                // magenta marks characters still being swept in: the shader draws them in the text color
                color: kind === "sweep" && p < 1 ? "#ff00ff" : "white"
            }
        }
    }

    // --- Logo -----------------------------------------------------------------------------------
    Item {
        id: logoBox
        anchors.centerIn: parent
        readonly property real ratio: logoImage.implicitHeight > 0 ? logoImage.implicitWidth / logoImage.implicitHeight : 4
        height: Math.min(scene.height * 0.14, scene.width * 0.36 / ratio)
        width: height * ratio
        Image {
            id: logoImage
            anchors.fill: parent
            source: scene.logo
            fillMode: Image.PreserveAspectFit
            smooth: true; mipmap: true
            cache: false
            visible: false
        }
        MultiEffect {
            anchors.fill: parent
            source: logoImage
            visible: scene.showLogo && logoImage.status === Image.Ready && !ascii.active
            colorization: 1.0
            colorizationColor: scene.accent
            brightness: 0.1
            shadowEnabled: true
            shadowColor: scene.accent
            shadowBlur: 1.0
            shadowOpacity: 0.75
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 0
            opacity: scene.effect === "particles" ? 0.35 : 0.9
            // static glow: an animated one would make Plasma redraw the whole desktop 60 times a second
        }
    }
}
