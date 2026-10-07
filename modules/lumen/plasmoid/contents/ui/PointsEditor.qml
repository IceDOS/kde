import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: editor
    // [{time, brightness}]; the parent reads it back on save.
    property var points: []
    readonly property var timeRe: /^(\d{1,2}:\d{2}|(sunrise|sunset)([+-]\d+)?)$/
    readonly property bool valid: points.length > 0 && points.every(p => timeRe.test(p.time))
    // "HH:MM" from the status, used to show when sun-relative points land today.
    property string sunrise: ""
    property string sunset: ""
    spacing: 0

    function clock(spec) {
        var m = spec.match(/^(sunrise|sunset)([+-]\d+)?$/);
        if (!m) return "";
        var base = m[1] === "sunrise" ? sunrise : sunset;
        if (!base) return "";
        var p = base.split(":");
        var t = ((Number(p[0]) * 60 + Number(p[1]) + Number(m[2] || 0)) % 1440 + 1440) % 1440;
        return String(Math.floor(t / 60)).padStart(2, "0") + ":" + String(t % 60).padStart(2, "0");
    }

    function patch(i, key, value) {
        var p = JSON.parse(JSON.stringify(points));
        if (key === null) p.splice(i, 1); else p[i][key] = value;
        points = p;
    }

    Repeater {
        model: editor.points
        delegate: RowLayout {
            required property var modelData
            required property int index
            Layout.fillWidth: true
            PlasmaComponents.TextField {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 6
                text: modelData.time
                color: editor.timeRe.test(text) ? Kirigami.Theme.textColor : Kirigami.Theme.negativeTextColor
                onEditingFinished: editor.patch(index, "time", text.trim())
            }
            PlasmaComponents.Label {
                text: editor.clock(modelData.time)
                Layout.preferredWidth: Kirigami.Units.gridUnit * 2.5
                font: Kirigami.Theme.smallFont
                opacity: 0.6
            }
            PlasmaComponents.Slider {
                id: level
                Layout.fillWidth: true
                from: 0
                to: 100
                stepSize: 1
                value: modelData.brightness
                // Patching rebuilds the rows, so only commit once the drag ends.
                onPressedChanged: if (!pressed) editor.patch(index, "brightness", Math.round(value))
            }
            PlasmaComponents.Label {
                text: Math.round(level.value) + "%"
                Layout.preferredWidth: Kirigami.Units.gridUnit * 2
                horizontalAlignment: Text.AlignRight
            }
            PlasmaComponents.ToolButton {
                icon.name: "list-remove"
                enabled: editor.points.length > 1
                onClicked: editor.patch(index, null)
            }
        }
    }
    RowLayout {
        PlasmaComponents.ToolButton {
            icon.name: "list-add"
            text: i18n("Add point")
            onClicked: editor.points = editor.points.concat([{ time: "12:00", brightness: 50 }])
        }
        Kirigami.ContextualHelpButton {
            toolTipText: i18n("A time is a clock time (07:00), or sunrise or sunset shifted by minutes: sunset+30 is 30 minutes after sunset, sunrise-15 is 15 minutes before sunrise. Brightness ramps between points.")
        }
    }
}
