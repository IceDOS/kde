import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

Page {
    id: meter
    required property var app
    readonly property var content: meter.column

    PlasmaExtras.PlaceholderMessage {
        visible: app.d === null
        Layout.fillWidth: true
        iconName: "utilities-energy-monitor"
        text: app.lastError || i18n("Waiting for data")
    }

    RowLayout {
        visible: app.d !== null
        Layout.fillWidth: true
        Kirigami.Heading {
            level: 1
            text: app.d ? Math.round(app.d.total_w) + " W" : ""
        }
        Item { Layout.fillWidth: true }
        ColumnLayout {
            spacing: 0
            Kirigami.Heading {
                level: 3
                Layout.alignment: Qt.AlignRight
                text: app.d ? app.money(app.d.cost_per_hour) + i18n("/h") : ""
            }
            PlasmaComponents.Label {
                Layout.alignment: Qt.AlignRight
                opacity: 0.7
                text: app.d ? app.money(app.d.unit_price) + i18n("/kWh") + (app.d.plug ? i18n(", smart plug") : "") : ""
            }
        }
    }

    RowLayout {
        visible: app.d !== null
        Layout.fillWidth: true
        spacing: 0
        Repeater {
            model: app.d ? app.d.windows : []
            delegate: ColumnLayout {
                required property var modelData
                // A share of the fixed popup width; the row's own width depends on its children.
                Layout.preferredWidth: content.width / Math.max(1, app.d.windows.length)
                spacing: 0
                PlasmaComponents.Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: modelData.label
                    opacity: 0.6
                }
                Kirigami.Heading {
                    level: 4
                    Layout.alignment: Qt.AlignHCenter
                    text: app.money(modelData.cost)
                }
                PlasmaComponents.Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: (modelData.wh / 1000).toFixed(2) + " kWh"
                    font: Kirigami.Theme.smallFont
                    opacity: 0.6
                }
            }
        }
    }

    ColumnLayout {
        visible: app.d !== null
        Layout.fillWidth: true
        spacing: 0

        Canvas {
            id: spark
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 2.5
            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                var h = app.d ? app.d.history : [];
                if (h.length < 2) return;
                var lo = Math.min.apply(null, h), hi = Math.max.apply(null, h);
                // Headroom below the low point keeps small swings from looking like spikes.
                var range = Math.max(10, hi - lo);
                lo = Math.max(0, lo - range);
                hi += range * 0.15;
                var px = i => i * width / (h.length - 1);
                var py = v => height - (v - lo) / (hi - lo) * height;
                ctx.beginPath();
                ctx.moveTo(0, height);
                for (var i = 0; i < h.length; i++) ctx.lineTo(px(i), py(h[i]));
                ctx.lineTo(width, height);
                ctx.closePath();
                var fill = ctx.createLinearGradient(0, 0, 0, height);
                fill.addColorStop(0, Qt.alpha(Kirigami.Theme.highlightColor, 0.35));
                fill.addColorStop(1, Qt.alpha(Kirigami.Theme.highlightColor, 0.0));
                ctx.fillStyle = fill;
                ctx.fill();
                ctx.beginPath();
                for (var j = 0; j < h.length; j++) {
                    if (j === 0) ctx.moveTo(px(j), py(h[j])); else ctx.lineTo(px(j), py(h[j]));
                }
                ctx.strokeStyle = Kirigami.Theme.highlightColor;
                ctx.lineWidth = 1.5;
                ctx.lineJoin = "round";
                ctx.stroke();
            }
            Connections {
                target: app
                function onDChanged() { spark.requestPaint(); }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            opacity: 0.6
            PlasmaComponents.Label {
                text: i18n("last 5 min")
                font: Kirigami.Theme.smallFont
                Layout.fillWidth: true
            }
            PlasmaComponents.Label {
                font: Kirigami.Theme.smallFont
                text: app.d && app.d.history.length
                    ? i18n("low %1 W · peak %2 W", Math.round(Math.min.apply(null, app.d.history)), Math.round(Math.max.apply(null, app.d.history)))
                    : ""
            }
        }
    }

    RowLayout {
        visible: app.d !== null
        Layout.fillWidth: true
        Kirigami.Heading {
            level: 4
            text: i18n("Power")
            Layout.fillWidth: true
        }
        PlasmaComponents.Label {
            text: i18n("now")
            opacity: 0.6
            Layout.preferredWidth: Kirigami.Units.gridUnit * 4
            horizontalAlignment: Text.AlignRight
        }
        PlasmaComponents.Label {
            text: app.compWindow() ? app.compWindow().label : ""
            opacity: 0.6
            Layout.preferredWidth: Kirigami.Units.gridUnit * 4
            horizontalAlignment: Text.AlignRight
        }
    }
    ColumnLayout {
        visible: app.d !== null
        Layout.fillWidth: true
        spacing: 0
        Repeater {
            // Parts drawing nothing (no extra loads configured, say) are left out.
            model: app.d ? Object.keys(app.d.watts).filter(c => app.d.watts[c] >= 0.05).sort((a, b) => app.d.watts[b] - app.d.watts[a]) : []
            delegate: RowLayout {
                required property string modelData
                Layout.fillWidth: true
                PlasmaComponents.Label {
                    text: app.labels[modelData] || modelData
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 7
                    elide: Text.ElideRight
                }
                PlasmaComponents.ProgressBar {
                    Layout.fillWidth: true
                    from: 0
                    to: app.d.total_w
                    value: app.d.watts[modelData]
                }
                PlasmaComponents.Label {
                    text: app.d.watts[modelData].toFixed(1) + " W"
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                    horizontalAlignment: Text.AlignRight
                }
                PlasmaComponents.Label {
                    text: app.money(app.componentCost(modelData))
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                    horizontalAlignment: Text.AlignRight
                    opacity: 0.7
                }
            }
        }
    }

    // prime-agent's local models: marginal GPU draw, already inside the GPU row above.
    RowLayout {
        visible: app.ai !== null
        Layout.fillWidth: true
        Kirigami.Heading {
            level: 4
            text: i18n("Local AI")
            Layout.fillWidth: true
        }
        PlasmaComponents.Label {
            opacity: 0.6
            text: app.ai && app.ai.active
                ? i18n("%1 W now, part of GPU", Math.round(app.ai.watts))
                : i18n("part of GPU")
        }
    }
    RowLayout {
        visible: app.ai !== null
        Layout.fillWidth: true
        spacing: 0
        Repeater {
            model: app.ai ? app.ai.windows : []
            delegate: ColumnLayout {
                required property var modelData
                Layout.preferredWidth: content.width / Math.max(1, app.ai.windows.length)
                spacing: 0
                PlasmaComponents.Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: modelData.label
                    opacity: 0.6
                }
                PlasmaComponents.Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: app.money(modelData.cost)
                }
            }
        }
    }

    Kirigami.Heading {
        visible: app.d !== null
        level: 4
        text: i18n("Usage")
    }
    GridLayout {
        visible: app.d !== null
        Layout.fillWidth: true
        columns: 3
        rowSpacing: 0

        PlasmaComponents.Label { text: i18n("CPU"); Layout.preferredWidth: Kirigami.Units.gridUnit * 7 }
        PlasmaComponents.ProgressBar { Layout.fillWidth: true; from: 0; to: 100; value: app.d ? app.d.usage.cpu_pct : 0 }
        PlasmaComponents.Label {
            text: app.d ? app.d.usage.cpu_pct.toFixed(0) + " %" : ""
            // Spans the Power rows' watt and cost columns plus the 5 px layout spacing, so bars end together.
            Layout.preferredWidth: Kirigami.Units.gridUnit * 8 + 5
            horizontalAlignment: Text.AlignRight
        }
        PlasmaComponents.Label { text: i18n("GPU") }
        PlasmaComponents.ProgressBar { Layout.fillWidth: true; from: 0; to: 100; value: app.d ? app.d.usage.gpu_pct : 0 }
        PlasmaComponents.Label {
            text: app.d ? app.d.usage.gpu_pct.toFixed(0) + " %" : ""
            Layout.preferredWidth: Kirigami.Units.gridUnit * 8 + 5
            horizontalAlignment: Text.AlignRight
        }
        PlasmaComponents.Label { text: i18n("Disks") }
        PlasmaComponents.Label {
            Layout.columnSpan: 2
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
            text: app.d ? i18n("%1 read · %2 write", app.rate(app.d.usage.disk_read_bps), app.rate(app.d.usage.disk_write_bps)) : ""
        }
        PlasmaComponents.Label { text: i18n("Network") }
        PlasmaComponents.Label {
            Layout.columnSpan: 2
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
            text: app.d ? "↓ " + app.rate(app.d.usage.net_rx_bps) + " · ↑ " + app.rate(app.d.usage.net_tx_bps) : ""
        }
    }
}
