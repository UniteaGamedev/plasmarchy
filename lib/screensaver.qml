// Plasmarchy screensaver (in the style of the Omarchy screensaver).
// Usage: qml screensaver.qml -- <colors.json> <text> <effect-seconds>
// Quits on a key press, click or mouse movement.
import QtQuick
import QtQuick.Window

Window {
    id: win
    visible: true
    visibility: Window.FullScreen
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    color: pal.background
    title: "Plasmarchy Screensaver"

    readonly property var args: Qt.application.arguments
    readonly property string colorsFile: args[args.length - 3]
    readonly property string text: args[args.length - 2]
    readonly property real effectSeconds: Number(args[args.length - 1]) || 14

    property var pal: ({ background: "#111111", foreground: "#dddddd", muted: "#555555",
                         accent: "#88aaff", palette: ["#88aaff"] })
    property var cells: []          // filled cells of the lettering: {c, r}
    property int gridCols: 0
    property int gridRows: 0
    property real cell: 14
    property real t: 0              // seconds since the effect started
    property int effect: 0
    property var reveal: []         // decrypt: reveal time per cell
    property var drops: []          // rain: drop per screen column
    readonly property var effects: ["decrypt", "rain", "wave"]
    readonly property string glyphs: "アカサタナハマヤラワ01<>/\\|{}[]#$%&*+=?"
    property point startMouse: Qt.point(-1, -1)

    function loadColors() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + colorsFile, false)
        xhr.send()
        pal = JSON.parse(xhr.responseText)
    }

    function hexToRgb(h) {
        var n = parseInt(h.slice(1), 16)
        return [(n >> 16) & 255, (n >> 8) & 255, n & 255]
    }

    function blend(a, b, f) {
        var x = hexToRgb(a), y = hexToRgb(b)
        return "rgb(" + [0, 1, 2].map(i => Math.round(x[i] + (y[i] - x[i]) * f)).join(",") + ")"
    }

    function paletteAt(pos) {      // pos 0..1 across the palette, smoothly blended
        var p = pal.palette, n = p.length
        var f = ((pos % 1) + 1) % 1 * n
        var i = Math.floor(f)
        return blend(p[i % n], p[(i + 1) % n], f - i)
    }

    function randomGlyph() { return glyphs.charAt(Math.floor(Math.random() * glyphs.length)) }

    // Turn text into block letters: draw on a hidden canvas and sample it
    function buildCells() {
        var ctx = mask.getContext("2d")
        var h = mask.height
        ctx.fillStyle = "black"
        ctx.fillRect(0, 0, mask.width, h)
        ctx.fillStyle = "white"
        ctx.font = "bold " + Math.round(h * 0.25) + "px sans-serif"   // fits at 2x scaling including descenders
        ctx.textBaseline = "top"
        ctx.fillText(text, 8, h * 0.1)
        // sample a grid only (the canvas is larger than expected due to scaling)
        var img = ctx.getImageData(0, 0, mask.width, mask.height)
        var W = img.width, H = img.height, data = img.data
        var step = Math.round(6 * W / mask.width)
        var raw = [], minC = 1e9, maxC = -1, minR = 1e9, maxR = -1
        for (var y = step >> 1; y < H; y += step)
            for (var x = step >> 1; x < W; x += step)
                if (data[(y * W + x) * 4] > 128) {
                    var c = (x / step) | 0, r = (y / step) | 0
                    raw.push({ c: c, r: r })
                    if (c < minC) minC = c; if (c > maxC) maxC = c
                    if (r < minR) minR = r; if (r > maxR) maxR = r
                }
        if (maxC < 0) return
        gridCols = maxC - minC + 1
        gridRows = maxR - minR + 1
        var list = raw.map(p => ({ c: p.c - minC, r: p.r - minR }))
        cells = list
        cell = Math.max(6, Math.floor(Math.min(win.width * 0.72 / gridCols, win.height * 0.45 / gridRows)))
    }

    function startEffect(i) {
        effect = i
        t = 0
        reveal = cells.map(() => Math.random() * 2.5)
        var cols = Math.ceil(win.width / cell)
        drops = []
        for (var c = 0; c < cols; c++)
            drops.push({ y: -Math.random() * win.height, speed: 4 + Math.random() * 10, color: Math.random() })
    }

    Canvas {
        id: mask
        visible: false
        width: 2400
        height: 400            // larger canvases stay empty (white image) - room comes from a smaller font
        canvasSize: Qt.size(2400, 400)
        onAvailableChanged: if (available) { win.buildCells(); win.startEffect(Math.floor(Math.random() * 3)) }
    }

    Canvas {
        id: screen
        anchors.fill: parent
        renderStrategy: Canvas.Threaded
        onPaint: {
            var ctx = getContext("2d")
            ctx.globalAlpha = 1
            ctx.shadowBlur = 0
            ctx.fillStyle = win.pal.background
            ctx.fillRect(0, 0, width, height)
            if (!win.cells.length) return

            var s = win.cell
            var ox = (width - win.gridCols * s) / 2
            var oy = (height - win.gridRows * s) / 2
            var fade = Math.min(1, win.t / 0.8, (win.effectSeconds - win.t) / 0.8)
            ctx.globalAlpha = Math.max(0, fade)
            ctx.font = Math.round(s * 0.95) + "px monospace"
            ctx.textAlign = "center"
            ctx.textBaseline = "middle"
            var name = win.effects[win.effect]

            if (name === "rain") {
                for (var d = 0; d < win.drops.length; d++) {
                    var drop = win.drops[d]
                    for (var k = 0; k < 14; k++) {
                        var yy = drop.y - k * s
                        if (yy < -s || yy > height) continue
                        ctx.fillStyle = k === 0 ? win.pal.foreground : win.paletteAt(drop.color)
                        ctx.globalAlpha = Math.max(0, fade) * (k === 0 ? 0.9 : 0.35 * (1 - k / 14))
                        ctx.fillText(win.randomGlyph(), d * s + s / 2, yy)
                    }
                }
                ctx.globalAlpha = Math.max(0, fade)
            }

            ctx.shadowColor = win.pal.accent
            ctx.shadowBlur = name === "rain" ? s * 1.2 : s * 0.6
            for (var i = 0; i < win.cells.length; i++) {
                var cc = win.cells[i]
                var x = ox + cc.c * s, y = oy + cc.r * s
                var pos = cc.c / win.gridCols
                if (name === "decrypt") {
                    if (win.t < win.reveal[i]) {
                        ctx.fillStyle = win.pal.muted
                        ctx.fillText(win.randomGlyph(), x + s / 2, y + s / 2)
                        continue
                    }
                    ctx.fillStyle = win.paletteAt(pos * 0.6 + win.t * 0.03)
                } else if (name === "wave") {
                    y += Math.sin(win.t * 2.2 + cc.c * 0.18) * s * 0.9
                    ctx.fillStyle = win.paletteAt(pos - win.t * 0.12)
                } else {
                    ctx.fillStyle = win.pal.accent
                }
                ctx.fillRect(x + s * 0.08, y + s * 0.08, s * 0.84, s * 0.84)
            }
            ctx.shadowBlur = 0
        }
    }

    Timer {
        interval: 33
        running: true
        repeat: true
        onTriggered: {
            win.t += 0.033
            if (win.effects[win.effect] === "rain")
                for (var d = 0; d < win.drops.length; d++) {
                    var drop = win.drops[d]
                    drop.y += drop.speed
                    if (drop.y - 14 * win.cell > win.height) { drop.y = -Math.random() * 200; drop.color = Math.random() }
                }
            if (win.t >= win.effectSeconds)
                win.startEffect((win.effect + 1 + Math.floor(Math.random() * 2)) % 3)
            screen.requestPaint()
        }
    }

    // Quit on input (mouse movement only after a short grace period, against jitter)
    Timer { id: grace; interval: 1200 }
    Item {
        anchors.fill: parent
        focus: true
        Keys.onPressed: Qt.quit()
    }
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.BlankCursor
        onClicked: Qt.quit()
        onPositionChanged: (m) => {
            if (grace.running) return
            if (win.startMouse.x < 0) { win.startMouse = Qt.point(m.x, m.y); return }
            if (Math.abs(m.x - win.startMouse.x) + Math.abs(m.y - win.startMouse.y) > 12) Qt.quit()
        }
    }

    Component.onCompleted: { loadColors(); grace.start(); requestActivate() }
}
