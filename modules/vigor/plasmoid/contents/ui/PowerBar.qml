import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

// Session actions along the bottom of every tab; Plasma's own confirmation settings apply.
PlasmaExtras.PlasmoidHeading {
    id: bar
    required property var app
    // Firmware setup skips the logout dialog, so it takes a second click within a few seconds.
    property bool armFirmware: false

    position: PlasmaExtras.PlasmoidHeading.Footer

    Timer {
        id: disarm
        interval: 4000
        onTriggered: bar.armFirmware = false
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Repeater {
            model: [
                { id: "lock", icon: "system-lock-screen", text: i18n("Lock"), show: bar.app.sm.canLock },
                { id: "switch", icon: "system-switch-user", text: i18n("Switch user"), show: bar.app.sm.canSwitchUser },
                { id: "logout", icon: "system-log-out", text: i18n("Log out"), show: bar.app.sm.canLogout },
                { id: "suspend", icon: "system-suspend", text: i18n("Sleep"), show: bar.app.sm.canSuspend },
                { id: "hibernate", icon: "system-suspend-hibernate", text: i18n("Hibernate"), show: bar.app.sm.canHibernate },
                { id: "reboot", icon: "system-reboot", text: i18n("Restart"), show: bar.app.sm.canReboot },
                { id: "firmware", icon: "preferences-system-startup", text: i18n("Restart into firmware setup"),
                  show: bar.app.s !== null && bar.app.s.can_firmware },
                { id: "shutdown", icon: "system-shutdown", text: i18n("Shut down"), show: bar.app.sm.canShutdown }
            ]
            delegate: PlasmaComponents.ToolButton {
                required property var modelData
                visible: modelData.show
                Layout.fillWidth: true
                icon.name: modelData.icon
                display: PlasmaComponents.AbstractButton.IconOnly
                text: modelData.id === "firmware" && bar.armFirmware ? i18n("Click again to restart into firmware setup") : modelData.text
                checked: modelData.id === "firmware" && bar.armFirmware
                PlasmaComponents.ToolTip.text: text
                PlasmaComponents.ToolTip.visible: hovered
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                onClicked: {
                    if (modelData.id === "firmware" && !bar.armFirmware) {
                        bar.armFirmware = true;
                        disarm.restart();
                        return;
                    }
                    bar.armFirmware = false;
                    bar.app.expanded = false;
                    bar.app.perform(modelData.id);
                }
            }
        }
    }
}
