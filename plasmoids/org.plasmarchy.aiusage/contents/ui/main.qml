// AI assistant: chat with the connected AI (Claude Code, Cursor, …, local model), conversation mode via
// button, hotkey or wake word, usage limits. Only the icon sits in the panel.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    readonly property string bin: "\"$HOME/.local/bin/plasmarchy\""
    readonly property string mono: "JetBrainsMono Nerd Font"
    readonly property string robot: String.fromCodePoint(0xF06A9)
    property var usage: null
    property var providers: []
    property bool actions: false
    property var messages: []           // {role: "user"|"assistant"|"error", text, provider, notice}
    property bool thinking: false
    property bool newChat: false
    property var voice: ({ stt: false, tts: false })
    property var settings: null         // "plasmarchy settings get"
    property string busy: ""            // running settings action
    property real micLevel: -999        // last microphone test (dB)
    property int page: 0                // 0 = chat, 1 = settings
    readonly property bool speakAnswers: settings ? settings.speakAnswers : false
    readonly property string hotkey: settings ? settings.hotkey : "Meta+Shift+Space"

    readonly property var limits: usage && usage.limits && usage.limits.available ? usage.limits.windows : []

    function b64(s) { return Qt.btoa(s) }   // Qt.btoa already encodes as UTF-8
    function run(args) { exec.connectSource("sh -c 'exec " + bin + " " + args + "'") }
    // While recording a new hotkey, global shortcuts must not fire (the old one would start a conversation)
    function blockShortcuts(on) {
        exec.connectSource("busctl --user call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel blockGlobalShortcuts b " + on)
    }
    function timeOf(iso, withDay) {
        if (!iso) return ""
        var d = new Date(iso)
        if (d <= new Date()) return i18n("now")
        return withDay ? d.toLocaleString(Qt.locale(), "ddd HH:mm") : d.toLocaleTimeString(Qt.locale(), "HH:mm")
    }
    function addMessage(m) { messages = messages.concat([m]) }

    function ask(text) {
        text = text.trim()
        if (!text || thinking) return
        addMessage({ role: "user", text: text })
        thinking = true
        var args = "ask --b64 " + (newChat ? "--new " : "")
        if (Plasmoid.configuration.provider !== "auto") args += "--provider " + Plasmoid.configuration.provider + " "
        run(args + b64(text))
        newChat = false
    }
    function resetChat() { messages = []; newChat = true; run("voice stop") }
    function startTalk() { root.expanded = false; run("talk") }

    P5Support.DataSource {
        id: exec
        engine: "executable"
        onNewData: (source, data) => {
            disconnectSource(source)
            var out
            try { out = JSON.parse(data.stdout) } catch (e) { out = null }
            if (source.indexOf(" ai-usage ") >= 0) { if (out) root.usage = out }
            else if (source.indexOf(" providers") >= 0) { if (out) { root.providers = out.providers; root.actions = out.actions } }
            else if (source.indexOf(" voice status") >= 0) { if (out) root.voice = out }
            else if (source.indexOf(" assistant history") >= 0) {
                if (out && !root.thinking && !root.newChat)
                    root.messages = out.map(m => ({ role: m.role, text: m.text, provider: m.provider, notice: m.notice }))
            }
            else if (source.indexOf(" assistant set ") >= 0) { root.run("providers") }
            else if (source.indexOf(" settings get") >= 0) { if (out) root.settings = out }
            else if (source.indexOf(" settings set64 ") >= 0) {
                root.busy = ""
                if (!out) root.addMessage({ role: "error", text: i18n("Couldn't save the setting: %1", (data.stderr || "").trim().slice(-200)) })
                root.run("settings get"); root.run("providers"); root.run("voice status")
            }
            else if (source.indexOf(" settings level") >= 0) { root.busy = ""; if (out) root.micLevel = out.db }
            else if (source.indexOf(" settings sample") >= 0) { root.busy = "" }
            else if (source.indexOf(" voice mic") >= 0) {
                root.addMessage({ role: "error", text: out && out.source ? i18n("Microphone: %1", out.source.replace(/^alsa_input\./, ""))
                                                                         : i18n("No microphone found") })
            }
            else if (source.indexOf(" ask ") >= 0) {
                root.thinking = false
                if (!out) root.addMessage({ role: "error", text: i18n("No answer received.") })
                else if (out.error) root.addMessage({ role: "error", text: out.error, provider: out.provider })
                else {
                    root.addMessage({ role: "assistant", text: out.answer, provider: out.provider, notice: out.notice || "" })
                    if (root.speakAnswers && root.voice.tts)
                        root.run("voice speak " + root.b64((out.notice ? out.notice + " " : "") + out.answer))
                }
            }
        }
    }
    Timer {   // usage + limits; --notify sends a notification when a threshold is reached
        interval: 60000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: root.run("ai-usage --json --notify")
    }
    Component.onCompleted: { run("providers"); run("voice status"); run("settings get") }
    onExpandedChanged: if (root.expanded) { run("providers"); run("voice status"); run("assistant history"); run("ai-usage --json"); run("settings get") }

    // No preferredRepresentation: the widget lives in the system tray, which hosts the popup
    toolTipMainText: i18n("AI Assistant")
    toolTipSubText: (limits.length ? limits.map(w => w.name + " " + w.used + " %").join(" · ") + "\n" : "")
                    + i18n("%1 to talk", root.hotkey)

    compactRepresentation: MouseArea {
        Layout.minimumWidth: icon.implicitWidth + Kirigami.Units.smallSpacing * 2
        onClicked: root.expanded = !root.expanded
        PC3.Label {
            id: icon
            anchors.centerIn: parent
            text: root.robot
            font.family: root.mono
            font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.2
        }
    }

    fullRepresentation: PlasmaExtras.Representation {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 24   // same as the system tray popups (Wi-Fi, Bluetooth, volume)
        Layout.preferredHeight: Kirigami.Units.gridUnit * 24
        Layout.minimumWidth: Kirigami.Units.gridUnit * 20
        Layout.minimumHeight: Kirigami.Units.gridUnit * 18
        collapseMarginsHint: true

        header: PlasmaExtras.PlasmoidHeading {
            RowLayout {
                anchors.fill: parent
                spacing: Kirigami.Units.smallSpacing
                PC3.ToolButton { visible: root.page === 1; icon.name: "go-previous-symbolic"; onClicked: root.page = 0
                                 PC3.ToolTip { text: i18n("Back to chat") } }
                // the tray already shows the title; only the settings page names itself
                Kirigami.Heading { level: 3; text: root.page === 1 ? i18n("Settings") : ""
                                   font.family: root.mono; Layout.fillWidth: true }
                PC3.ComboBox {
                    id: providerBox
                    visible: root.page === 0
                    readonly property var choices: [{ id: "auto", name: i18n("Automatic") }].concat(root.providers)
                    model: choices.map(p => p.name)
                    currentIndex: Math.max(0, choices.findIndex(p => p.id === Plasmoid.configuration.provider))
                    onActivated: (i) => Plasmoid.configuration.provider = choices[i].id
                    PC3.ToolTip { text: i18n("Which AI answers first (on limits/errors the next one takes over automatically)") }
                }
                PC3.Button {
                    visible: root.voice.stt && root.page === 0
                    icon.name: "audio-input-microphone-symbolic"
                    text: i18n("Talk")
                    onClicked: root.startTalk()
                    PC3.ToolTip { text: i18n("Talk to your computer (%1)", root.hotkey) }
                }
                PC3.ToolButton {
                    visible: root.page === 0
                    icon.name: "application-menu-symbolic"
                    onClicked: menu.open()
                    PC3.ToolTip { text: i18n("Menu") }
                    QQC2.Menu {
                        id: menu
                        y: parent.height
                        QQC2.MenuItem { text: i18n("New chat"); icon.name: "list-add-symbolic"; onTriggered: root.resetChat() }
                        QQC2.MenuItem { text: i18n("Settings …"); icon.name: "configure-symbolic"; onTriggered: { root.page = 1; root.run("settings get") } }
                    }
                }
            }
        }

        StackLayout {
          anchors.fill: parent
          anchors.margins: Kirigami.Units.largeSpacing
          currentIndex: root.page

          ColumnLayout {
            spacing: Kirigami.Units.largeSpacing

            // --- Limits ---------------------------------------------------------------------
            Repeater {
                model: root.limits
                delegate: ColumnLayout {
                    required property var modelData
                    readonly property bool over: new Date(modelData.resets_at) <= new Date()
                    Layout.fillWidth: true
                    spacing: 2
                    RowLayout {
                        PC3.Label { text: modelData.name; opacity: 0.8; Layout.fillWidth: true }
                        PC3.Label {
                            text: over ? i18n("reset") : i18n("%1% left · resets %2", 100 - modelData.used, root.timeOf(modelData.resets_at, modelData.id !== "five_hour"))
                            font.family: root.mono; opacity: 0.8
                            color: !over && 100 - modelData.used <= 20 ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                        }
                    }
                    PC3.ProgressBar { Layout.fillWidth: true; from: 0; to: 100; value: over ? 0 : modelData.used }
                }
            }

            Kirigami.Separator { Layout.fillWidth: true }

            // --- Chat -----------------------------------------------------------------------
            ListView {
                id: chat
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Kirigami.Units.largeSpacing
                model: root.messages
                onCountChanged: Qt.callLater(positionViewAtEnd)   // new message -> scroll to the end
                QQC2.ScrollBar.vertical: PC3.ScrollBar { id: chatBar }
                // Messages never extend under the scroll bar (it appears as soon as the chat overflows)
                readonly property real rowWidth: width - chatBar.width - Kirigami.Units.smallSpacing

                PlasmaExtras.PlaceholderMessage {
                    anchors.centerIn: parent
                    width: parent.width - Kirigami.Units.gridUnit * 2
                    visible: root.messages.length === 0
                    iconName: "dialog-messages"
                    text: root.providers.length ? i18n("Ask me anything") : i18n("No AI connected")
                    explanation: root.providers.length
                        ? i18n("Type or talk (%1)", root.hotkey) + (root.actions ? " · " + i18n("I can open apps and change the theme and volume") : "")
                        : i18n("Sign in to e.g. Claude Code or set up a local model: plasmarchy llm setup")
                }

                delegate: Column {
                    required property var modelData
                    readonly property bool mine: modelData.role === "user"
                    width: chat.rowWidth
                    spacing: 2
                    PC3.Label {   // notice, e.g. "Claude reached its limit - answer from Local"
                        visible: !!modelData.notice
                        text: modelData.notice || ""
                        width: parent.width
                        wrapMode: Text.WordWrap
                        opacity: 0.65
                        font: Kirigami.Theme.smallFont
                    }
                    Item {
                        width: parent.width
                        height: bubble.height
                        readonly property real pad: Kirigami.Units.largeSpacing
                        readonly property real maxW: width * (mine ? 0.85 : 1)
                        Text {   // measure the natural text width (without wrapping)
                            id: measure
                            visible: false
                            text: modelData.text
                            textFormat: mine ? Text.PlainText : Text.MarkdownText
                            font: Kirigami.Theme.defaultFont
                        }
                        Rectangle {
                            id: bubble
                            anchors.right: mine ? parent.right : undefined
                            width: Math.min(parent.maxW, measure.implicitWidth + parent.pad * 2 + 2)
                            height: body.implicitHeight + parent.pad * 2
                            radius: Kirigami.Units.cornerRadius * 2
                            color: mine ? Qt.alpha(Kirigami.Theme.highlightColor, 0.25)
                                 : modelData.role === "error" ? Qt.alpha(Kirigami.Theme.neutralTextColor, 0.15)
                                 : Qt.alpha(Kirigami.Theme.textColor, 0.06)
                            TextEdit {
                                id: body
                                x: Kirigami.Units.largeSpacing; y: Kirigami.Units.largeSpacing
                                width: bubble.width - Kirigami.Units.largeSpacing * 2
                                text: modelData.text
                                textFormat: mine ? TextEdit.PlainText : TextEdit.MarkdownText
                                wrapMode: TextEdit.Wrap
                                readOnly: true
                                selectByMouse: true
                                color: Kirigami.Theme.textColor
                                selectionColor: Kirigami.Theme.highlightColor
                                font: Kirigami.Theme.defaultFont
                                onLinkActivated: (url) => Qt.openUrlExternally(url)
                            }
                        }
                    }
                }

                footer: Item {
                    width: chat.width
                    height: root.thinking ? Kirigami.Units.gridUnit * 2 : 0
                    RowLayout {
                        visible: root.thinking
                        anchors.verticalCenter: parent.verticalCenter
                        PC3.BusyIndicator { implicitWidth: Kirigami.Units.iconSizes.small; implicitHeight: implicitWidth; running: parent.visible }
                        PC3.Label { text: i18n("thinking …"); opacity: 0.7 }
                    }
                }
            }

            // --- Input -----------------------------------------------------------------------
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                PC3.TextField {
                    id: input
                    Layout.fillWidth: true
                    placeholderText: i18n("Message the AI …")
                    onAccepted: { root.ask(text); text = "" }
                    Component.onCompleted: forceActiveFocus()
                }
                PC3.ToolButton {
                    icon.name: "document-send-symbolic"
                    enabled: input.text.trim().length > 0 && !root.thinking
                    onClicked: { root.ask(input.text); input.text = "" }
                    PC3.ToolTip { text: i18n("Send") }
                }
            }
          }

          SettingsPage { app: root }
        }
    }
}
