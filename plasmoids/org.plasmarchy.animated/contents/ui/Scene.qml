// The animated scene itself - independent of Plasma, so it can also be rendered offscreen for previews.
// Effects: "aurora" (soft drifting color clouds), "particles" (rising glow dots, logo sparkling from particles),
// "rain" (digital rain). All of them draw the branding logo in the accent color in the middle.
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import QtQuick.Particles

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

    readonly property real unit: Math.min(width, height) / 100
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
                x: scene.width * (0.15 + 0.17 * index) - r
                y: scene.height * (index % 2 ? 0.65 : 0.3) - r
                opacity: 0.42
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
                // Lissajous-like drift: different period per axis and blob
                SequentialAnimation on x {
                    running: scene.running; loops: Animation.Infinite
                    NumberAnimation { to: scene.width * (0.1 + 0.2 * ((blob.index + 2) % 5)) - blob.r; duration: (21000 + blob.index * 4300) / scene.speed; easing.type: Easing.InOutSine }
                    NumberAnimation { to: scene.width * (0.15 + 0.17 * blob.index) - blob.r; duration: (19000 + blob.index * 3700) / scene.speed; easing.type: Easing.InOutSine }
                }
                SequentialAnimation on y {
                    running: scene.running; loops: Animation.Infinite
                    NumberAnimation { to: scene.height * (blob.index % 2 ? 0.25 : 0.72) - blob.r; duration: (17000 + blob.index * 5100) / scene.speed; easing.type: Easing.InOutSine }
                    NumberAnimation { to: scene.height * (blob.index % 2 ? 0.65 : 0.3) - blob.r; duration: (23000 + blob.index * 2900) / scene.speed; easing.type: Easing.InOutSine }
                }
                SequentialAnimation on opacity {
                    running: scene.running; loops: Animation.Infinite
                    NumberAnimation { to: 0.6; duration: (9000 + blob.index * 1700) / scene.speed; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0.3; duration: (11000 + blob.index * 1300) / scene.speed; easing.type: Easing.InOutSine }
                }
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
        SequentialAnimation on opacity {
            running: scene.running && scene.effect === "particles"; loops: Animation.Infinite
            NumberAnimation { to: 0.6; duration: 5000 / scene.speed; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.0; duration: 5000 / scene.speed; easing.type: Easing.InOutSine }
        }
    }

    ParticleSystem {
        id: particles
        anchors.fill: parent
        running: scene.effect === "particles"
        paused: !scene.running
        ImageParticle {
            groups: ["dust"]
            source: "qrc:///particleresources/glowdot.png"
            color: scene.accent
            colorVariation: 0.15
            alpha: 0.55
            alphaVariation: 0.3
            entryEffect: ImageParticle.Fade
        }
        ImageParticle {
            groups: ["dust2"]
            source: "qrc:///particleresources/glowdot.png"
            color: scene.col(0)
            alpha: 0.45
            alphaVariation: 0.3
            entryEffect: ImageParticle.Fade
        }
        ImageParticle {
            groups: ["logo"]
            source: "qrc:///particleresources/glowdot.png"
            color: scene.accent
            colorVariation: 0.1
            alpha: 0.9
            entryEffect: ImageParticle.Fade
        }
        Emitter {
            group: "dust"
            width: parent.width; height: scene.unit * 5
            anchors.bottom: parent.bottom
            emitRate: 22 * scene.speed
            startTime: 26000          // start with a screen already full of particles
            lifeSpan: 26000 / scene.speed; lifeSpanVariation: 6000
            size: scene.unit * 1.2; sizeVariation: scene.unit * 0.9; endSize: scene.unit * 0.4
            velocity: AngleDirection { angle: 270; angleVariation: 12; magnitude: scene.unit * 3.6 * scene.speed; magnitudeVariation: scene.unit * 1.2 }
        }
        Emitter {
            group: "dust2"
            width: parent.width; height: parent.height
            emitRate: 8 * scene.speed
            startTime: 14000
            lifeSpan: 14000 / scene.speed; lifeSpanVariation: 4000
            size: scene.unit * 0.6; sizeVariation: scene.unit * 0.4
            velocity: AngleDirection { angle: 270; angleVariation: 40; magnitude: scene.unit * 0.6 * scene.speed }
        }
        Emitter {
            group: "logo"
            enabled: scene.showLogo
            x: logoBox.x; y: logoBox.y; width: logoBox.width; height: logoBox.height
            shape: MaskShape { source: scene.logo }
            emitRate: 160 * scene.speed
            startTime: 3000
            lifeSpan: 2600; lifeSpanVariation: 1200
            size: scene.unit * 1.1; sizeVariation: scene.unit * 0.5; endSize: scene.unit * 0.2
        }
        Wander {
            groups: ["dust", "dust2"]
            xVariance: scene.unit * 4
            pace: scene.unit * 2
        }
    }

    // --- Rain: columns of glyphs falling ------------------------------------------------------------
    Item {
        id: rain
        anchors.fill: parent
        visible: scene.effect === "rain"
        readonly property real cell: Math.max(14, scene.unit * 1.9)
        readonly property int columns: Math.ceil(width / cell)
        readonly property string glyphs: "ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄ0123456789<>{}[]=+*#ABCDEF"
        function column(n) {
            var s = []
            for (var i = 0; i < n; i++) s.push(glyphs[Math.floor(Math.random() * glyphs.length)])
            return s.join("\n")
        }
        Repeater {
            model: scene.effect === "rain" ? rain.columns : 0
            delegate: Item {
                id: drop
                required property int index
                property int len: 8 + Math.floor(Math.random() * 18)
                x: index * rain.cell
                width: rain.cell
                height: glyphText.implicitHeight
                y: -height
                Text {
                    id: glyphText
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: rain.column(drop.len)
                    color: drop.index % 7 === 0 ? scene.col(0) : scene.accent
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: rain.cell * 0.82
                    lineHeight: 1.05
                }
                Rectangle {   // fade the tail into the background
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0; color: scene.darkBackground }
                        GradientStop { position: 0.85; color: Qt.alpha(scene.darkBackground, 0) }
                    }
                }
                SequentialAnimation on y {
                    running: scene.running && scene.effect === "rain"
                    loops: Animation.Infinite
                    PauseAnimation { duration: Math.random() * 9000 / scene.speed }
                    NumberAnimation {
                        from: -drop.height; to: scene.height
                        duration: (6000 + Math.random() * 9000) / scene.speed
                    }
                    ScriptAction { script: { drop.len = 8 + Math.floor(Math.random() * 18); glyphText.text = rain.column(drop.len) } }
                }
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
            visible: scene.showLogo && logoImage.status === Image.Ready
            colorization: 1.0
            colorizationColor: scene.accent
            brightness: 0.1
            shadowEnabled: true
            shadowColor: scene.accent
            shadowBlur: 1.0
            shadowOpacity: 0.9
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 0
            opacity: scene.effect === "particles" ? 0.35 : 0.9
            SequentialAnimation on shadowOpacity {   // slow breathing glow
                running: scene.running; loops: Animation.Infinite
                NumberAnimation { to: 0.4; duration: 4000 / scene.speed; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0.9; duration: 4000 / scene.speed; easing.type: Easing.InOutSine }
            }
        }
    }
}
