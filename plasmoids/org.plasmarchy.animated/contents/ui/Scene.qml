// The animated scene itself - independent of Plasma, so it can also be rendered offscreen for previews.
// Effects: "aurora" (soft drifting color clouds), "particles" (rising glow dots, logo sparkling from particles),
// "rain" (digital rain), "logo" (the ASCII logo assembling itself like in the screensaver).
// Except for "logo", they draw the branding logo in the accent color in the middle (unless showLogo is off).
import QtQuick
import QtQuick.Shapes
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

    // Shared clock at 25 frames per second instead of 60: slow wallpaper motion looks the same, but Plasma only
    // has to redraw the desktop 25 times a second (much less CPU and battery).
    property real clock: 0               // seconds
    Timer {
        interval: 40; repeat: true
        running: scene.running && (scene.effect === "aurora" || scene.effect === "particles" || ascii.active)
        onTriggered: scene.clock += 0.04 * scene.speed
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
    Item {
        anchors.fill: parent
        visible: scene.effect === "aurora"
        Repeater {
            model: scene.effect === "aurora" ? 5 : 0
            delegate: Shape {
                id: blob
                required property int index
                readonly property real r: scene.unit * (38 + index * 9)
                readonly property color c: index === 0 ? scene.accent : scene.col(index - 1)
                width: r * 2; height: r * 2
                x: scene.width * px - r
                y: scene.height * py - r
                opacity: 0.45 + 0.15 * Math.sin(scene.clock * 2 * Math.PI / (20 + index * 3))
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeWidth: -1
                    fillGradient: RadialGradient {
                        centerX: blob.r; centerY: blob.r; centerRadius: blob.r
                        focalX: blob.r; focalY: blob.r
                        GradientStop { position: 0; color: blob.c }
                        GradientStop { position: 0.45; color: Qt.alpha(blob.c, 0.45) }
                        GradientStop { position: 1; color: Qt.alpha(blob.c, 0) }
                    }
                    PathAngleArc { centerX: blob.r; centerY: blob.r; radiusX: blob.r; radiusY: blob.r; startAngle: 0; sweepAngle: 360 }
                }
                // Lissajous-like drift from the shared clock: different period per axis and blob
                readonly property real px: 0.15 + 0.17 * index + 0.12 * Math.sin(scene.clock * 2 * Math.PI / (40 + index * 8))
                readonly property real py: (index % 2 ? 0.45 : 0.5) + 0.22 * Math.sin(scene.clock * 2 * Math.PI / (44 + index * 7) + index)
            }
        }
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

    // Rising glow dots, computed from the shared 25 fps clock (Qt's particle system would simulate every
    // particle 60 times a second). Each dot: start position, speed and size from a fixed random seed.
    Item {
        id: dust
        anchors.fill: parent
        visible: scene.effect === "particles"
        readonly property var dots: {
            var out = []
            for (var i = 0; i < 110; i++)
                out.push({ x: Math.random(), phase: Math.random(), v: 0.5 + Math.random(), s: 0.4 + Math.random() * 1.1,
                           c: Math.random() < 0.75 })
            return out
        }
        Repeater {
            model: dust.visible ? dust.dots : []
            delegate: Rectangle {
                required property var modelData
                readonly property real travel: scene.height * 1.15
                readonly property real pos: (modelData.phase * travel + scene.clock * modelData.v * scene.unit * 2.4) % travel
                width: scene.unit * modelData.s; height: width; radius: width / 2
                x: modelData.x * scene.width + Math.sin(scene.clock * 0.4 + modelData.phase * 6.28) * scene.unit * 2
                y: scene.height + scene.unit * 2 - pos
                color: modelData.c ? scene.accent : scene.col(0)
                opacity: Math.min(1, pos / (travel * 0.15)) * (1 - pos / travel) * 0.8
                Rectangle {   // soft halo
                    anchors.centerIn: parent
                    width: parent.width * 3; height: width; radius: width / 2
                    color: parent.color
                    opacity: 0.18
                }
            }
        }
        // the logo sparkles: dots twinkling on random cells of the ASCII logo
        Repeater {
            model: dust.visible && scene.showLogo ? Math.min(90, ascii.cells.length) : 0
            delegate: Rectangle {
                required property int index
                readonly property var cell: ascii.cells[(index * 7919) % ascii.cells.length]
                readonly property real tw: Math.max(0, Math.sin(scene.clock * (1.1 + cell.seed) + cell.seed * 40))
                // the ASCII art and the logo image cover the same shape: map the cell onto the image
                x: logoBox.x + (cell.c + 0.5) / ascii.cols * logoBox.width - width / 2
                y: logoBox.y + (cell.r + 0.5) / Math.max(1, ascii.lines.length) * logoBox.height - height / 2
                width: scene.unit * (0.5 + tw * 0.7); height: width; radius: width / 2
                color: Qt.tint(scene.accent, Qt.rgba(1, 1, 1, 0.35))
                opacity: Math.pow(tw, 3)
            }
        }
    }

    // --- Rain: digital rain like in The Matrix --------------------------------------------------
    // Drawn on a canvas that is never cleared, only darkened a little every frame: each column's bright head
    // leaves a trail that fades out, and random characters inside the trails keep flickering.
    // Performance: drawn at half resolution and scaled up by the GPU (a quarter of the pixels to darken and
    // upload per frame), no blur effects - the soft upscaling gives the glyphs a slight glow for free.
    Canvas {
        id: matrix
        width: Math.ceil(parent.width / 2)
        height: Math.ceil(parent.height / 2)
        scale: 2
        transformOrigin: Item.TopLeft
        smooth: true
        visible: scene.effect === "rain"
        renderStrategy: Canvas.Threaded
        readonly property real cell: Math.max(8, scene.unit * 0.85)
        readonly property int columns: Math.ceil(width / cell)
        readonly property string glyphs: "ｦｱｳｴｵｶｷｹｺｻｼｽｾｿﾀﾂﾃﾅﾆﾇﾈﾊﾋﾎﾏﾐﾑﾒﾓﾔﾕﾗﾘﾜ012345789Z:・.\"=*+-<>¦｜"
        property var drops: []        // per column: head position (in cells) and speed
        property bool fresh: true
        function glyph() { return glyphs[Math.floor(Math.random() * glyphs.length)] }
        function css(c, a) {   // the canvas wants CSS color strings
            return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + (a === undefined ? 1 : a) + ")"
        }
        function reset() {
            drops = []
            for (var i = 0; i < columns; i++)
                drops.push({ y: -Math.random() * height / cell, v: 0.35 + Math.random() * 0.75 })
            fresh = true
        }
        onColumnsChanged: reset()
        onVisibleChanged: if (visible) { reset(); requestPaint() }
        Timer {
            interval: 66          // ~15 frames per second: the classic look, and light on the CPU
            repeat: true
            running: matrix.visible && scene.running
            onTriggered: matrix.requestPaint()
        }
        onPaint: {
            var ctx = getContext("2d")
            var bg = scene.darkBackground
            if (fresh) {
                ctx.fillStyle = css(bg)
                ctx.fillRect(0, 0, width, height)
                fresh = false
            }
            ctx.fillStyle = css(bg, 0.075)                        // the fade that turns heads into trails
            ctx.fillRect(0, 0, width, height)
            ctx.font = Math.round(cell * 0.9) + "px \"Noto Sans CJK JP\""
            ctx.textAlign = "center"
            ctx.textBaseline = "top"
            var trail = css(scene.accent)
            var trailDim = css(scene.accent, 0.85)
            var head = css(Qt.tint(scene.foreground, Qt.rgba(1, 1, 1, 0.55)))
            for (var i = 0; i < drops.length; i++) {
                var d = drops[i]
                var x = i * cell + cell / 2
                var prev = Math.floor(d.y)
                d.y += d.v * scene.speed
                var row = Math.floor(d.y)
                if (row !== prev && row >= 0) {
                    ctx.fillStyle = trail                         // the old head becomes part of the trail
                    ctx.fillText(glyph(), x, prev * cell)
                    ctx.fillStyle = head                          // the new head is almost white
                    ctx.fillText(glyph(), x, row * cell)
                }
                if (Math.random() < 0.18 && row > 2) {            // flickering characters inside the trail
                    ctx.fillStyle = trailDim
                    ctx.fillText(glyph(), x, (row - 1 - Math.floor(Math.random() * 14)) * cell)
                }
                if (row * cell > height && Math.random() > 0.97)  // restart from the top at random
                    drops[i] = { y: -Math.random() * 12, v: 0.35 + Math.random() * 0.75 }
            }
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
        // color wave: changes 8 times a second (QML only re-evaluates the cells when the value really changes)
        readonly property real shimmer: Math.floor(scene.clock * 8) / 48 % 1
        onPhaseChanged: {
            var p = phase
            var newT = p < 4.2 ? p / 4.2 : p < 13.2 ? 1 : 1 + Math.pow((p - 13.2) / 1.8, 2)
            if (newT !== t) t = newT
        }
        readonly property int cycleNo: Math.floor(scene.clock / cycle)
        onCycleNoChanged: mode = (mode + 1) % modes.length

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
                // color: gradient across the logo, a wave running through it while it stands
                readonly property real g: (m.c / ascii.cols + ascii.shimmer) % 1
                color: kind === "sweep" && p < 1 ? scene.foreground
                     : Qt.tint(scene.col(Math.floor(g * 4)), Qt.alpha(scene.accent, 0.35 + 0.25 * Math.sin((g + m.r * 0.05) * Math.PI * 2)))
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
