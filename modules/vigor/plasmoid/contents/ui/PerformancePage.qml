import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

Page {
    id: perf
    required property var app

    readonly property var p: app.s ? app.s.profile : null
    readonly property var cpu: app.s ? app.s.cpu : null
    readonly property var names: ({
        "power-saver": i18n("Power Save"), "balanced": i18n("Balanced"), "performance": i18n("Performance")
    })

    readonly property var chips: ({
        k10temp: i18n("CPU"), zenpower: i18n("CPU"), coretemp: i18n("CPU"), cpu_thermal: i18n("CPU"),
        amdgpu: i18n("GPU"), radeon: i18n("GPU"), nouveau: i18n("GPU"), nvme: i18n("NVMe")
    })

    function chip(name) { return chips[name] || name; }

    function ghz(mhz) { return (mhz / 1000).toFixed(1); }

    PlasmaExtras.PlaceholderMessage {
        visible: perf.app.s === null
        Layout.fillWidth: true
        iconName: "speedometer"
        text: i18n("Waiting for data")
    }

    ColumnLayout {
        visible: perf.p !== null
        Layout.fillWidth: true
        spacing: 0

        PlasmaComponents.Slider {
            id: slider
            Layout.fillWidth: true
            from: 0
            to: perf.p ? Math.max(1, perf.p.available.length - 1) : 1
            stepSize: 1
            snapMode: PlasmaComponents.Slider.SnapAlways
            enabled: perf.p !== null && perf.p.available.length > 1
            PlasmaComponents.ToolTip.text: perf.p && perf.p.source === "cpufreq"
                ? i18n("Sets the CPU governor and boost; power-profiles-daemon has no driver for this CPU.")
                : i18n("Handled by power-profiles-daemon.")
            PlasmaComponents.ToolTip.visible: hovered
            PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
            // Dragging breaks a value binding, so resync on every status update instead.
            function sync() {
                if (!pressed) value = perf.p ? Math.max(0, perf.p.available.indexOf(perf.p.active)) : 0;
            }
            Component.onCompleted: sync()
            Connections {
                target: perf.app
                function onSChanged() { slider.sync(); }
            }
            onMoved: {
                var name = perf.p.available[Math.round(value)];
                if (name && name !== perf.p.active) perf.app.run("profile " + name);
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Repeater {
                model: perf.p ? perf.p.available : []
                delegate: PlasmaComponents.Label {
                    required property string modelData
                    required property int index
                    Layout.fillWidth: true
                    horizontalAlignment: index === 0 ? Text.AlignLeft
                        : index === perf.p.available.length - 1 ? Text.AlignRight : Text.AlignHCenter
                    text: perf.names[modelData] || modelData
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    font.bold: perf.p && modelData === perf.p.active
                    opacity: font.bold ? 1 : 0.6
                }
            }
        }
    }

    PlasmaComponents.Label {
        visible: perf.p !== null && (perf.p.degraded !== "" || perf.p.holds.length > 0)
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font: Kirigami.Theme.smallFont
        color: Kirigami.Theme.neutralTextColor
        text: !perf.p ? "" : [perf.p.degraded ? i18n("Reduced: %1", perf.p.degraded) : ""]
            .concat(perf.p.holds.map(h => i18n("%1 holds %2", h.app, perf.names[h.profile] || h.profile)))
            .filter(x => x).join("\n")
    }

    // Two label/value pairs per row keeps the facts to a few lines.
    GridLayout {
        visible: perf.cpu !== null && perf.cpu.governor !== null
        Layout.fillWidth: true
        columns: 4
        rowSpacing: 0
        columnSpacing: Kirigami.Units.smallSpacing

        component Key: PlasmaComponents.Label { opacity: 0.6 }
        component Val: PlasmaComponents.Label { Layout.fillWidth: true; elide: Text.ElideRight }

        Key { text: i18n("Clock") }
        Val { text: perf.cpu && perf.cpu.mhz ? i18n("%1 / %2 GHz", perf.ghz(perf.cpu.mhz), perf.ghz(perf.cpu.peak_mhz)) : "-" }
        Key { text: i18n("Boost") }
        Val {
            text: !perf.cpu || perf.cpu.boost === null ? "-"
                : perf.cpu.boost ? i18n("%1 GHz", perf.ghz(perf.cpu.max_mhz)) : i18n("off")
        }
        Key { text: i18n("Governor") }
        Val { text: perf.cpu ? perf.cpu.governor : "" }
        Key { text: i18n("Up") }
        Val { text: perf.app.s && perf.app.s.uptime ? perf.app.duration(perf.app.s.uptime) : "-" }
    }

    Flow {
        visible: perf.app.s !== null
        Layout.fillWidth: true
        spacing: Kirigami.Units.largeSpacing

        Repeater {
            model: perf.app.s ? perf.app.s.sensors.temps : []
            delegate: PlasmaComponents.Label {
                required property var modelData
                text: perf.chip(modelData.chip) + " " + Math.round(modelData.c) + "°"
                color: modelData.c >= 85 ? Kirigami.Theme.negativeTextColor
                    : modelData.c >= 70 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
                PlasmaComponents.ToolTip.text: modelData.chip + (modelData.label ? " " + modelData.label : "")
                PlasmaComponents.ToolTip.visible: hover.hovered
                HoverHandler { id: hover }
            }
        }
        Repeater {
            model: perf.app.s ? perf.app.s.sensors.fans : []
            delegate: PlasmaComponents.Label {
                required property var modelData
                text: i18n("%1 fan %2 rpm", perf.chip(modelData.chip), modelData.rpm)
                opacity: 0.8
            }
        }
    }
}
