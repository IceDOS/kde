import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

Page {
    id: devs
    required property var app

    readonly property var list: app.s ? app.s.devices : []
    readonly property var kinds: ({
        "battery": [i18n("Battery"), "battery-good"], "ups": [i18n("UPS"), "battery-ups"],
        "mouse": [i18n("Mouse"), "input-mouse"], "keyboard": [i18n("Keyboard"), "input-keyboard"],
        "phone": [i18n("Phone"), "smartphone"], "tablet": [i18n("Tablet"), "tablet"],
        "gaming-input": [i18n("Controller"), "input-gamepad"], "pen": [i18n("Pen"), "input-tablet"],
        "touchpad": [i18n("Touchpad"), "input-touchpad"], "headset": [i18n("Headset"), "audio-headset"],
        "speakers": [i18n("Speakers"), "audio-speakers"], "headphones": [i18n("Headphones"), "audio-headphones"],
        "media-player": [i18n("Media player"), "multimedia-player"], "computer": [i18n("Computer"), "computer"],
        "remote-control": [i18n("Remote"), "input-remote"], "printer": [i18n("Printer"), "printer"],
        "camera": [i18n("Camera"), "camera-photo"], "wearable": [i18n("Wearable"), "watch"],
        "bluetooth": [i18n("Bluetooth device"), "preferences-system-bluetooth"]
    })
    readonly property var levels: ({
        "low": i18n("Low"), "critical": i18n("Critical"), "normal": i18n("Normal"), "high": i18n("High"), "full": i18n("Full")
    })
    readonly property var levelPct: ({ "critical": 5, "low": 20, "normal": 55, "high": 80, "full": 100 })
    readonly property var states: ({
        "charging": i18n("Charging"), "discharging": i18n("Discharging"), "full": i18n("Fully charged"),
        "empty": i18n("Empty"), "pending-charge": i18n("Not charging"), "pending-discharge": i18n("Waiting to discharge")
    })

    function kind(d) { return kinds[d.kind] || [d.kind, "battery"]; }

    function detail(d) {
        var parts = [states[d.state] || ""];
        if (d.state === "discharging" && d.time_to_empty) parts.push(i18n("%1 left", app.duration(d.time_to_empty)));
        if (d.state === "charging" && d.time_to_full) parts.push(i18n("full in %1", app.duration(d.time_to_full)));
        if (d.rate_w) parts.push(d.rate_w.toFixed(1) + " W");
        return parts.filter(x => x).join(" · ");
    }

    RowLayout {
        visible: devs.app.s !== null
        Layout.fillWidth: true
        Kirigami.Icon {
            source: devs.app.s && devs.app.s.on_battery ? "battery-discharging" : "ac-adapter"
            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
            Layout.preferredHeight: Layout.preferredWidth
        }
        PlasmaComponents.Label {
            Layout.fillWidth: true
            text: devs.app.s && devs.app.s.on_battery ? i18n("Running on battery") : i18n("Plugged in")
        }
    }

    PlasmaExtras.PlaceholderMessage {
        visible: devs.app.s !== null && devs.list.length === 0
        Layout.fillWidth: true
        iconName: "battery-missing"
        text: i18n("No devices report a battery")
        explanation: i18n("Wireless mice, keyboards, headsets, controllers and phones appear here once UPower or Bluetooth sees them.")
    }

    Repeater {
        model: devs.list
        delegate: RowLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Icon {
                source: devs.kind(modelData)[1]
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredHeight: Layout.preferredWidth
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                RowLayout {
                    Layout.fillWidth: true
                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: modelData.model || devs.kind(modelData)[0]
                        font.bold: modelData.power_supply
                    }
                    PlasmaComponents.Label {
                        text: modelData.percent !== null ? Math.round(modelData.percent) + " %" : devs.levels[modelData.level] || ""
                        color: (modelData.percent !== null ? modelData.percent <= 15 : ["low", "critical"].includes(modelData.level))
                            ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                    }
                }
                PlasmaComponents.ProgressBar {
                    Layout.fillWidth: true
                    from: 0
                    to: 100
                    // Devices that only report a coarse level get an approximate bar.
                    value: modelData.percent !== null ? modelData.percent : devs.levelPct[modelData.level] || 0
                }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font: Kirigami.Theme.smallFont
                    opacity: 0.6
                    text: [devs.kind(modelData)[0], devs.detail(modelData)].filter(x => x).join(" · ")
                }
            }
        }
    }
}
