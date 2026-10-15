// Wallpaper settings (Desktop -> Configure Desktop and Wallpaper). Colors follow the Plasmarchy theme.
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page
    property string cfg_effect
    property alias cfg_showLogo: showLogo.checked
    property alias cfg_pauseWhenCovered: pause.checked
    property real cfg_speed

    QQC2.ComboBox {
        Kirigami.FormData.label: i18n("Animation:")
        readonly property var values: ["aurora", "particles", "rain", "logo"]
        model: [i18n("Aurora: drifting color clouds"), i18n("Particles: rising light, sparkling logo"), i18n("Code rain"),
                i18n("Logo animation: like the screensaver")]
        currentIndex: Math.max(0, values.indexOf(page.cfg_effect))
        onActivated: (i) => page.cfg_effect = values[i]
    }
    QQC2.Slider {
        Kirigami.FormData.label: i18n("Speed:")
        from: 0.3; to: 2.5; stepSize: 0.1
        value: page.cfg_speed
        onMoved: page.cfg_speed = value
    }
    QQC2.CheckBox {
        id: showLogo
        Kirigami.FormData.label: i18n("Logo:")
        text: i18n("Show the logo (change it with \"plasmarchy branding\")")
    }
    QQC2.CheckBox {
        id: pause
        Kirigami.FormData.label: i18n("Battery:")
        text: i18n("Pause while a maximized or fullscreen window covers the desktop")
    }
    QQC2.Label {
        text: i18n("Colors follow the active Plasmarchy theme.")
        opacity: 0.6
    }
}
