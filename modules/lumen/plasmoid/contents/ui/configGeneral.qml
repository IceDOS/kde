import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    property alias cfg_refreshSec: refresh.value
    property alias cfg_showPercent: showPercent.checked

    QQC2.SpinBox {
        id: refresh
        Kirigami.FormData.label: i18n("Refresh every (s):")
        from: 1
        to: 60
    }
    QQC2.CheckBox {
        id: showPercent
        Kirigami.FormData.label: i18n("Panel shows:")
        text: i18n("Average brightness")
    }
}
