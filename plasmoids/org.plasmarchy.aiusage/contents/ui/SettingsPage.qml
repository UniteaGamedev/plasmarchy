// Assistant settings page: AI, voice, wake word.
// Values come from "plasmarchy settings get"; changes go through "plasmarchy settings set64".
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

QQC2.ScrollView {
    id: page
    required property var app          // PlasmoidItem (run, settings, busy, micLevel)
    readonly property var s: app.settings
    contentWidth: availableWidth
    QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

    component Section: Kirigami.Heading {
        level: 4
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.largeSpacing
        color: Kirigami.Theme.highlightColor
    }
    // Caption above its control(s); children are stacked full-width
    component Field: ColumnLayout {
        property string label
        default property alias content: inner.data
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        PC3.Label { text: parent.label; opacity: 0.85 }
        ColumnLayout { id: inner; Layout.fillWidth: true; spacing: Kirigami.Units.smallSpacing }
    }

    function set(key, value) { app.busy = key; app.run("settings set64 " + key + " " + Qt.btoa(String(value))) }
    function nameOf(list, id) { var x = (list || []).find(e => e.id === id); return x ? x.name : id }

    ColumnLayout {
        width: page.availableWidth - Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.largeSpacing

        PC3.Label { visible: !page.s; text: i18n("Loading settings …"); opacity: 0.7 }

        ColumnLayout {
            visible: !!page.s
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing

            // ================================ AI ================================
            Section { text: i18n("AI") }

            Field {
                label: i18n("Preferred AI:")
                PC3.ComboBox {
                    Layout.fillWidth: true; Layout.minimumWidth: Kirigami.Units.gridUnit * 5   // shrink + elide instead of widening the page
                    readonly property var choices: page.s ? [{ id: "auto", name: i18n("Automatic (first connected)") }].concat(page.s.providers) : []
                    model: choices.map(c => c.name)
                    currentIndex: page.s ? Math.max(0, choices.findIndex(c => c.id === page.s.provider)) : 0
                    onActivated: (i) => page.set("PROVIDER", choices[i].id)
                }
            }

            Field {
                label: i18n("Fallback order:")
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Repeater {
                        model: page.s ? page.s.order : []
                        delegate: RowLayout {
                            required property string modelData
                            required property int index
                            Layout.fillWidth: true
                            readonly property bool ready: page.s.providers.some(p => p.id === modelData)
                            PC3.Label { text: (index + 1) + ". " + page.nameOf(page.s.allProviders, modelData); Layout.preferredWidth: Kirigami.Units.gridUnit * 6 }
                            PC3.Label { text: ready ? i18n("connected") : i18n("not set up"); opacity: ready ? 0.8 : 0.45
                                        color: ready ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.textColor }
                            Item { Layout.fillWidth: true }
                            PC3.ToolButton { icon.name: "arrow-up-symbolic"; enabled: index > 0
                                onClicked: { var o = page.s.order.slice(); o.splice(index - 1, 0, o.splice(index, 1)[0]); page.set("PROVIDER_ORDER", o.join(" ")) } }
                            PC3.ToolButton { icon.name: "arrow-down-symbolic"; enabled: index < page.s.order.length - 1
                                onClicked: { var o = page.s.order.slice(); o.splice(index + 1, 0, o.splice(index, 1)[0]); page.set("PROVIDER_ORDER", o.join(" ")) } }
                        }
                    }
                    PC3.Label {
                        text: i18n("If an AI hits its limit or can't be reached, the next one answers automatically.")
                        opacity: 0.6; font: Kirigami.Theme.smallFont; wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                }
            }

            Field {
                label: i18n("Local model:")
                RowLayout {
                    PC3.TextField { id: localModel; text: page.s ? page.s.localModel : ""; Layout.preferredWidth: Kirigami.Units.gridUnit * 7
                                    onEditingFinished: if (page.s && text !== page.s.localModel) page.set("LOCAL_MODEL", text) }
                    PC3.Label {
                        text: !page.s ? "" : page.s.ollama.modelReady ? i18n("ready") : page.s.ollama.running ? i18n("model missing") : i18n("not set up")
                        color: page.s && page.s.ollama.modelReady ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.neutralTextColor
                    }
                }
            }
            PC3.Label {
                visible: page.s && !page.s.ollama.modelReady
                text: i18n("Set up in a terminal: %1", "plasmarchy llm setup")
                opacity: 0.6; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            }

            Field {
                label: i18n("Desktop actions:")
                PC3.Switch {
                    text: i18n("Open apps, change theme & volume")
                    checked: page.s ? page.s.actions : false
                    onToggled: page.set("ACTIONS", checked ? "on" : "off")
                }
            }

            // Limit alerts: pick thresholds instead of typing numbers
            Field {
                label: i18n("Limit alerts:")
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    readonly property var options: [50, 25, 20, 10, 5]
                    readonly property var selected: page.s ? page.s.notifyLeft.split(/\s+/).filter(x => x).map(Number) : []
                    id: alerts
                    Flow {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        Repeater {
                            model: alerts.options
                            delegate: PC3.Button {
                                required property int modelData
                                checkable: true
                                checked: alerts.selected.indexOf(modelData) >= 0
                                text: i18n("%1% left", modelData)
                            icon.name: checked ? "checkmark-symbolic" : ""
                                onToggled: {
                                    var sel = alerts.options.filter(v => v === modelData ? checked : alerts.selected.indexOf(v) >= 0)
                                    page.set("NOTIFY_LEFT", sel.join(" "))
                                }
                            }
                        }
                    }
                    PC3.Label {
                        text: alerts.selected.length ? i18n("A notification appears when only this much of a Claude plan limit is left.")
                                                     : i18n("No alerts – select one or more thresholds.")
                        opacity: 0.6; font: Kirigami.Theme.smallFont; wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                }
            }

            // ============================== Voice ==============================
            Section { text: i18n("Voice") }

            PC3.Label {
                visible: page.s && !page.s.voice.ready
                text: i18n("Voice isn't set up yet. In a terminal: %1", "plasmarchy voice setup")
                wrapMode: Text.WordWrap; Layout.fillWidth: true
                color: Kirigami.Theme.neutralTextColor
            }

            Field {
                label: i18n("Talk hotkey:")
                HotkeyField {
                    sequence: page.s ? page.s.hotkey : ""
                    enabled: page.app.busy !== "HOTKEY"
                    onRecordingToggled: (on) => page.app.blockShortcuts(on)
                    onAccepted: (seq) => page.set("HOTKEY", seq)
                }
            }

            Field {
                label: i18n("Microphone:")
                RowLayout {
                    PC3.ComboBox {
                        Layout.fillWidth: true; Layout.minimumWidth: Kirigami.Units.gridUnit * 5   // shrink + elide instead of widening the page
                        readonly property var choices: page.s ? page.s.voice.sources : []
                        model: choices.map(c => c.name.replace("Ryzen HD Audio Controller ", ""))
                        currentIndex: page.s ? Math.max(0, choices.findIndex(c => c.id === page.s.voice.source)) : 0
                        onActivated: (i) => page.set("VOICE_SOURCE", choices[i].id)
                    }
                    PC3.Button { text: i18n("Test"); icon.name: "audio-input-microphone-symbolic"; enabled: page.app.busy === ""
                                 onClicked: { page.app.busy = "level"; page.app.run("settings level " + (page.s.voice.source || "auto")) } }
                }
            }
            Field {
                label: i18n("Level:")
                visible: page.app.micLevel > -200
                ColumnLayout {
                    PC3.ProgressBar { from: -75; to: -15; value: page.app.micLevel; Layout.preferredWidth: Kirigami.Units.gridUnit * 11 }
                    PC3.Label {
                        text: page.app.micLevel > -45 ? i18n("Good – speech comes through")
                            : page.app.micLevel > -60 ? i18n("Quiet – move closer to the microphone")
                            : i18n("Barely any signal – choose another microphone")
                        font: Kirigami.Theme.smallFont; opacity: 0.75
                    }
                }
            }

            Field {
                label: i18n("Speech recognition:")
                PC3.ComboBox {
                    Layout.fillWidth: true; Layout.minimumWidth: Kirigami.Units.gridUnit * 5   // shrink + elide instead of widening the page
                    enabled: page.s && page.s.voice.ready
                    readonly property var choices: page.s ? page.s.voice.models : []
                    model: choices.map(c => c.name + (c.installed ? "" : " – " + i18n("download")))
                    currentIndex: page.s ? Math.max(0, choices.findIndex(c => c.id === page.s.voice.model)) : 0
                    onActivated: (i) => page.set("VOICE_MODEL", choices[i].id)
                }
            }
            Field {
                label: i18n("Voice:")
                RowLayout {
                    PC3.ComboBox {
                        Layout.fillWidth: true; Layout.minimumWidth: Kirigami.Units.gridUnit * 5   // shrink + elide instead of widening the page
                        enabled: page.s && page.s.voice.ttsReady
                        readonly property var choices: page.s ? page.s.voice.voices : []
                        model: choices.map(c => c.name + (c.installed ? "" : " – " + i18n("download")))
                        currentIndex: page.s ? Math.max(0, choices.findIndex(c => c.id === page.s.voice.tts)) : 0
                        onActivated: (i) => page.set("VOICE_TTS", choices[i].id)
                    }
                    PC3.ToolButton { icon.name: "media-playback-start-symbolic"; enabled: page.app.busy === "" && page.s && page.s.voice.ttsReady
                                     onClicked: { page.app.busy = "sample"; page.app.run("settings sample") }
                                     PC3.ToolTip { text: i18n("Play a sample") } }
                }
            }
            Field {
                label: i18n("Conversations:")
                PC3.Switch {
                    text: i18n("Fast model for spoken answers (Claude Haiku)")
                    checked: page.s ? page.s.fastVoice : true
                    onToggled: page.set("FAST_VOICE", checked ? "on" : "off")
                }
            }
            Field {
                label: i18n("Read aloud:")
                PC3.Switch {
                    text: i18n("Always read chat answers aloud")
                    checked: page.s ? page.s.speakAnswers : false
                    onToggled: page.set("SPEAK_ANSWERS", checked ? "on" : "off")
                }
            }
            Field {
                label: i18n("Follow-ups:")
                RowLayout {
                    PC3.SpinBox { from: 0; to: 30; value: page.s ? Number(page.s.voice.followUp) : 8
                                  onValueModified: page.set("FOLLOW_UP", value) }
                    PC3.Label { text: i18n("seconds of listening after an answer"); opacity: 0.7 }
                }
            }

            // ============================== Wake word ==============================
            Section { text: i18n("Wake word") }

            Field {
                label: i18n("Wake word:")
                RowLayout {
                    PC3.ComboBox {
                        Layout.fillWidth: true; Layout.minimumWidth: Kirigami.Units.gridUnit * 5   // shrink + elide instead of widening the page
                        enabled: page.s && page.s.voice.ready && page.app.busy !== "WAKE_WORD"
                        readonly property var choices: page.s ? page.s.wake.words : []
                        model: choices.map(c => c.name)
                        currentIndex: page.s ? Math.max(0, choices.findIndex(c => c.id === page.s.wake.word)) : 0
                        onActivated: (i) => page.set("WAKE_WORD", choices[i].id)
                    }
                    PC3.Label {
                        visible: page.s && page.s.wake.word !== "off"
                        text: page.s && page.s.wake.running ? "● " + i18n("listening") : "○ " + i18n("inactive")
                        color: page.s && page.s.wake.running ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.neutralTextColor
                    }
                }
            }
            Field {
                label: i18n("Sensitivity:")
                visible: page.s && page.s.wake.word !== "off"
                RowLayout {
                    PC3.Label { text: i18n("low"); opacity: 0.6 }
                    PC3.Slider {   // high sensitivity = low trigger threshold
                        from: 0.2; to: 0.8; stepSize: 0.05
                        value: page.s ? 1 - page.s.wake.sensitivity : 0.5
                        onMoved: page.set("WAKE_SENSITIVITY", (1 - value).toFixed(2))
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 8
                    }
                    PC3.Label { text: i18n("high"); opacity: 0.6 }
                }
            }
            PC3.Label {
                text: page.s && page.s.wake.word !== "off"
                      ? i18n("Pronounce it in English. The microphone then listens continuously – locally, nothing leaves your computer.")
                      : i18n("Without a wake word, conversations start only via the hotkey – the microphone stays off otherwise.")
                wrapMode: Text.WordWrap; Layout.fillWidth: true
                opacity: 0.6; font: Kirigami.Theme.smallFont
            }
        }

        RowLayout {
            visible: page.app.busy !== ""
            PC3.BusyIndicator { implicitWidth: Kirigami.Units.iconSizes.small; implicitHeight: implicitWidth; running: parent.visible }
            PC3.Label { text: page.app.busy === "level" ? i18n("Listening for 2 seconds – say something …")
                             : page.app.busy === "sample" ? i18n("Playing sample …") : i18n("Saving … (downloads can take a moment)")
                        opacity: 0.75 }
        }
        Item { height: Kirigami.Units.largeSpacing }
    }
}
