// Settings of the music widget (right click -> Configure): when to show it and how much text.
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property string cfg_show
    property alias cfg_showTitle: showTitle.checked
    property alias cfg_maxTitleWidth: maxWidth.value

    Kirigami.FormLayout {
        QQC2.ComboBox {
            id: showBox
            Kirigami.FormData.label: i18n("Show in the top bar:")
            readonly property var values: ["auto", "always", "off"]
            model: [i18n("While a player is running"), i18n("Always"), i18n("Never (hidden)")]
            currentIndex: Math.max(0, values.indexOf(cfg_show))
            onActivated: (i) => cfg_show = values[i]
        }
        QQC2.CheckBox {
            id: showTitle
            Kirigami.FormData.label: i18n("Title:")
            text: i18n("Show artist and title next to the icon")
        }
        QQC2.SpinBox {
            id: maxWidth
            Kirigami.FormData.label: i18n("Maximum width:")
            enabled: showTitle.checked
            from: 6; to: 40
        }
    }
}
