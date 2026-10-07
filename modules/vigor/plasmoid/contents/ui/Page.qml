import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// One scrollable tab; children stack in a padded column as wide as the popup.
PlasmaComponents.ScrollView {
    id: page
    default property alias items: content.data
    property alias column: content

    contentWidth: availableWidth
    QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff
    contentHeight: content.implicitHeight + 2 * Kirigami.Units.largeSpacing

    ColumnLayout {
        id: content
        x: Kirigami.Units.largeSpacing
        y: Kirigami.Units.largeSpacing
        width: page.availableWidth - 2 * Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing
    }
}
