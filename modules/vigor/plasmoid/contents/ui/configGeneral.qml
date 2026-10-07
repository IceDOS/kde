import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    property alias cfg_refreshSec: refresh.value
    property alias cfg_showWatts: showWatts.checked
    property alias cfg_showCost: showCost.checked

    QQC2.SpinBox {
        id: refresh
        Kirigami.FormData.label: i18n("Refresh every (s):")
        from: 1
        to: 60
    }
    QQC2.CheckBox {
        id: showWatts
        Kirigami.FormData.label: i18n("Panel shows:")
        text: i18n("Watts")
    }
    QQC2.CheckBox {
        id: showCost
        text: i18n("Cost per hour")
    }
}
