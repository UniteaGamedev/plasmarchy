// Menu button for the top bar. It registers as the launcher, so Plasma's Windows-key action
// ("activate launcher menu") and a click both open the Plasmarchy menu instead of a popup.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PC3
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root
    // The button itself is the only representation - there is no popup
    preferredRepresentation: fullRepresentation
    fullRepresentation: button
    compactRepresentation: button
    activationTogglesExpanded: false
    toolTipMainText: i18n("Menu")
    toolTipSubText: i18n("Apps, style, toggles, setup and system – also with the Windows key")

    function openMenu() { exec.connectSource("sh -c 'exec \"$HOME/.local/bin/plasmarchy\" menu'") }

    P5Support.DataSource {
        id: exec
        engine: "executable"
        onNewData: (source) => disconnectSource(source)
    }
    Connections {
        target: Plasmoid
        function onActivated() { root.openMenu() }
    }

    Component {
        id: button
        MouseArea {
            Layout.minimumWidth: glyph.implicitWidth + Kirigami.Units.largeSpacing
            Layout.preferredWidth: Layout.minimumWidth
            Layout.maximumWidth: Layout.minimumWidth
            implicitWidth: Layout.minimumWidth
            implicitHeight: glyph.implicitHeight
            hoverEnabled: true
            onClicked: root.openMenu()
            PC3.Label {
                id: glyph
                anchors.centerIn: parent
                text: String.fromCodePoint(0xF003B)   // nf-md-apps (grid), like the previous launcher icon
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.15
                color: parent.containsMouse ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
            }
        }
    }
}
