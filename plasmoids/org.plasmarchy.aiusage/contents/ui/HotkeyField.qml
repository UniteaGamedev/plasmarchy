// Hotkey recorder: click, press the new combination, done (Esc cancels).
// Emits the sequence as text in KDE notation ("Meta+Shift+Space"); the backend registers it with kglobalaccel.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

RowLayout {
    id: field
    property string sequence: ""
    property bool recording: false
    property string hint: ""
    signal accepted(string sequence)
    signal recordingToggled(bool on)

    function keyName(key, text) {
        if (key >= Qt.Key_A && key <= Qt.Key_Z) return String.fromCharCode(key)
        if (key >= Qt.Key_0 && key <= Qt.Key_9) return String.fromCharCode(key)
        if (key >= Qt.Key_F1 && key <= Qt.Key_F24) return "F" + (key - Qt.Key_F1 + 1)
        var named = {}
        named[Qt.Key_Space] = "Space"; named[Qt.Key_Return] = "Return"; named[Qt.Key_Enter] = "Enter"
        named[Qt.Key_Tab] = "Tab"; named[Qt.Key_Pause] = "Pause"; named[Qt.Key_Print] = "Print"
        named[Qt.Key_Home] = "Home"; named[Qt.Key_End] = "End"
        return named[key] || ""
    }
    function start() { hint = ""; recording = true; recordingToggled(true); catcher.forceActiveFocus() }
    function stop() { if (recording) { recording = false; recordingToggled(false) } }

    PC3.Button {
        id: button
        Layout.preferredWidth: Kirigami.Units.gridUnit * 11
        checkable: true
        checked: field.recording
        icon.name: field.recording ? "media-record-symbolic" : "input-keyboard-symbolic"
        text: field.recording ? i18n("Press the new keys …") : (field.sequence || i18n("None"))
        font.family: field.recording ? Kirigami.Theme.defaultFont.family : "JetBrainsMono Nerd Font"
        onClicked: field.recording ? field.stop() : field.start()
    }
    PC3.Label {
        text: field.hint || (field.recording ? i18n("Esc cancels") : "")
        opacity: 0.6
        font: Kirigami.Theme.smallFont
    }

    Item {
        id: catcher
        focus: field.recording
        Keys.onPressed: (event) => {
            if (!field.recording) return
            event.accepted = true
            if (event.key === Qt.Key_Escape) { field.stop(); return }
            var name = field.keyName(event.key)
            if (!name) return   // modifier alone or unsupported key: keep waiting
            var mods = []
            if (event.modifiers & Qt.MetaModifier) mods.push("Meta")
            if (event.modifiers & Qt.ControlModifier) mods.push("Ctrl")
            if (event.modifiers & Qt.AltModifier) mods.push("Alt")
            if (event.modifiers & Qt.ShiftModifier) mods.push("Shift")
            if (!mods.length && !/^F\d+$/.test(name) && name !== "Pause" && name !== "Print") {
                field.hint = i18n("Add a modifier (Meta, Ctrl, Alt or Shift)")
                return
            }
            var seq = mods.concat([name]).join("+")
            field.stop()
            if (seq !== field.sequence) field.accepted(seq)
        }
        onActiveFocusChanged: if (!activeFocus) field.stop()
    }
}
