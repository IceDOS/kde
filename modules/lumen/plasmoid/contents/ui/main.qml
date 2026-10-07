import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root

    property var d: null
    property string lastError: ""
    readonly property bool inTray: (Plasmoid.containmentDisplayHints & PlasmaCore.Types.ContainmentForcesSquarePlasmoids) !== 0
    readonly property bool paused: d !== null && d.paused_until !== null
    readonly property real avg: d && d.monitors.length
        ? d.monitors.reduce((s, m) => s + m.current, 0) / d.monitors.length : 0

    // Replaced with a store path at build time (icedos.nix).
    readonly property string lumen: "@lumen@"

    // Copy of d.config taken when editing starts, so polls don't overwrite unsaved changes.
    property var draft: null

    function startEdit() { draft = JSON.parse(JSON.stringify(d.config)); }
    function draftMonitor(label) {
        var m = draft.monitors.find(x => x.label === label);
        if (!m) {
            m = { label: label, enable: true, scale: 1.0, offset: 0, points: [] };
            draft.monitors.push(m);
        }
        return m;
    }
    function patchMonitor(label, fields) {
        Object.assign(draftMonitor(label), fields);
        draft = JSON.parse(JSON.stringify(draft)); // reassign so bindings see the change
    }
    function signedPct(v) { return (v > 0 ? "+" : "") + v + "%"; }
    function saveEdit() {
        run("edit " + sh(JSON.stringify(draft)));
        draft = null;
    }

    function sh(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }
    function hm(ts) { return Qt.formatTime(new Date(ts * 1000), "HH:mm"); }
    function mins(s) { var p = s.split(":"); return Number(p[0]) * 60 + Number(p[1]); }
    function run(args) { action.connectSource(lumen + " " + args); }
    function pausedText() {
        if (!paused) return "";
        return d.paused_until > 1e15 ? i18n("Paused") : i18n("Paused until %1", hm(d.paused_until));
    }
    function monitorStatus(m) {
        if (m.error) return m.error;
        if (m.target === null) return i18n("Not scheduled");
        if (m.awake === false) return i18n("Display off");
        if (m.held_until) return i18n("Manual until %1", hm(m.held_until));
        if (paused) return pausedText();
        var base = m.custom ? i18n("Own points") : i18n("Following schedule");
        if (m.offset) base += " " + signedPct(m.offset);
        return Math.abs(m.current - m.target) < 1 ? base : i18n("%1, moving to %2%", base, Math.round(m.target));
    }

    Plasmoid.icon: avg >= 50 ? "brightness-high" : "brightness-low"
    toolTipMainText: d ? i18n("Brightness %1%", Math.round(avg)) : i18n("Brightness schedule")
    toolTipSubText: d
        ? (paused ? pausedText() : i18n("Next: %1% at %2", d.next.brightness, d.next.at))
        : lastError

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Pause until next point")
            icon.name: "media-playback-pause"
            onTriggered: root.run("pause next")
        },
        PlasmaCore.Action {
            text: i18n("Pause for 1 hour")
            icon.name: "media-playback-pause"
            onTriggered: root.run("pause 60")
        },
        PlasmaCore.Action {
            text: i18n("Resume schedule")
            icon.name: "media-playback-start"
            enabled: root.paused
            onTriggered: root.run("resume")
        }
    ]

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            if (data["exit code"] !== 0) {
                root.d = null;
                root.lastError = data.stderr.trim() || i18n("lumen service is not running");
                return;
            }
            try {
                root.d = JSON.parse(data.stdout);
                root.lastError = "";
            } catch (e) {
                root.lastError = String(e);
            }
        }
    }

    // Actions; on success the daemon wakes within ~2 s, so poll again shortly after.
    P5Support.DataSource {
        id: action
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            if (data["exit code"] !== 0) root.lastError = data.stderr.trim();
            soon.restart();
        }
    }

    Timer {
        id: soon
        interval: 2500
        onTriggered: poll.triggered()
    }

    Timer {
        id: poll
        interval: Math.max(1, Plasmoid.configuration.refreshSec) * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: exec.connectSource(root.lumen + " status --json")
    }

    compactRepresentation: MouseArea {
        Layout.minimumWidth: root.inTray ? -1 : row.implicitWidth
        onClicked: root.expanded = !root.expanded
        // Scroll nudges every monitor by 5 % and holds them like any manual change.
        onWheel: wheel => {
            if (!root.d) return;
            var step = wheel.angleDelta.y > 0 ? 5 : -5;
            root.run("set all " + Math.max(0, Math.min(100, Math.round(root.avg + step))));
        }

        RowLayout {
            id: row
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing
            Kirigami.Icon {
                source: Plasmoid.icon
                Layout.fillWidth: root.inTray
                Layout.fillHeight: root.inTray
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredHeight: Layout.preferredWidth
                opacity: !root.d ? 0.5 : root.paused ? 0.7 : 1
            }
            PlasmaComponents.Label {
                visible: !root.inTray && Plasmoid.configuration.showPercent && root.d !== null
                text: Math.round(root.avg) + "%"
            }
        }
    }

    fullRepresentation: PlasmaComponents.ScrollView {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 24
        Layout.preferredHeight: Math.min(content.implicitHeight + 2 * Kirigami.Units.largeSpacing, Kirigami.Units.gridUnit * 40)
        contentWidth: availableWidth
        contentHeight: content.implicitHeight + 2 * Kirigami.Units.largeSpacing

        ColumnLayout {
            id: content
            x: Kirigami.Units.largeSpacing
            y: Kirigami.Units.largeSpacing
            width: parent.width - 2 * Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing * 2

            PlasmaExtras.PlaceholderMessage {
                visible: root.d === null
                Layout.fillWidth: true
                iconName: "brightness-high"
                text: root.lastError || i18n("Waiting for data")
            }

            // Keyed by index so a poll doesn't rebuild the rows mid-drag.
            Repeater {
                model: root.d ? root.d.monitors.length : 0
                delegate: RowLayout {
                    id: mon
                    required property int index
                    readonly property var m: root.d.monitors[index]
                    readonly property var cfg: root.draft
                        ? (root.draft.monitors.find(x => x.label === m.label)
                           || { enable: true, scale: 1.0, offset: 0, points: [] })
                        : null
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.largeSpacing

                    Kirigami.Icon {
                        source: "video-display-brightness"
                        Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                        Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                        Layout.alignment: Qt.AlignTop
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        RowLayout {
                            Layout.fillWidth: true
                            PlasmaComponents.Label {
                                text: mon.m.label
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                            PlasmaComponents.Label {
                                text: i18n("Brightness %1%", Math.round(slider.value))
                            }
                        }

                        PlasmaComponents.Slider {
                            id: slider
                            Layout.fillWidth: true
                            enabled: mon.m.awake !== false
                            from: 0
                            to: 100
                            stepSize: 1
                            // Wait for the drag to settle; each set is a D-Bus call and a hold.
                            onMoved: {
                                debounce.restart();
                                settle.restart();
                            }
                            Binding on value {
                                when: !slider.pressed && !settle.running
                                value: mon.m.current
                                restoreMode: Binding.RestoreNone
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            PlasmaComponents.Label {
                                Layout.fillWidth: true
                                text: root.monitorStatus(mon.m)
                                color: mon.m.error ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                                opacity: mon.m.error ? 1 : 0.7
                                font: Kirigami.Theme.smallFont
                                elide: Text.ElideRight
                            }
                            PlasmaComponents.ToolButton {
                                visible: mon.m.held_until !== null
                                text: i18n("Resume")
                                icon.name: "media-playback-start"
                                font: Kirigami.Theme.smallFont
                                onClicked: root.run("resume " + root.sh(mon.m.label))
                            }
                        }

                        // One line per monitor while editing: what it follows, plus a flat offset.
                        RowLayout {
                            visible: mon.cfg !== null
                            Layout.fillWidth: true
                            Layout.topMargin: Kirigami.Units.smallSpacing
                            PlasmaComponents.ComboBox {
                                id: mode
                                Layout.fillWidth: true
                                model: [i18n("Follow schedule"), i18n("Own points"), i18n("Not scheduled")]
                                currentIndex: !mon.cfg ? 0 : !mon.cfg.enable ? 2 : mon.cfg.points.length ? 1 : 0
                                onActivated: index => root.patchMonitor(mon.m.label, {
                                    enable: index !== 2,
                                    points: index === 1 ? JSON.parse(JSON.stringify(root.draft.points)) : []
                                })
                            }
                            PlasmaComponents.SpinBox {
                                visible: mode.currentIndex !== 2
                                from: -100; to: 100; stepSize: 5
                                value: mon.cfg ? mon.cfg.offset : 0
                                textFromValue: (v, locale) => root.signedPct(v)
                                valueFromText: (t, locale) => parseInt(t) || 0
                                onValueModified: root.patchMonitor(mon.m.label, { offset: value })
                                PlasmaComponents.ToolTip { text: i18n("Added to the schedule, e.g. -20% runs this monitor at 60% when the schedule says 80%") }
                            }
                        }
                        PointsEditor {
                            sunrise: root.d ? root.d.sunrise : ""
                            sunset: root.d ? root.d.sunset : ""
                            visible: mon.cfg !== null && mode.currentIndex === 1
                            Layout.fillWidth: true
                            Layout.topMargin: Kirigami.Units.smallSpacing
                            points: mon.cfg ? mon.cfg.points : []
                            onPointsChanged: if (root.draft && mode.currentIndex === 1) root.draftMonitor(mon.m.label).points = points
                        }
                    }

                    Timer {
                        id: debounce
                        interval: 300
                        onTriggered: root.run("set " + root.sh(mon.m.label) + " " + Math.round(slider.value))
                    }
                    // Keeps the slider where it was dropped until the daemon reports the new value.
                    Timer {
                        id: settle
                        interval: 4000
                    }
                }
            }

            RowLayout {
                visible: root.d !== null
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                Kirigami.Icon {
                    source: "chronometer"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                    Layout.alignment: Qt.AlignTop
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    RowLayout {
                        Layout.fillWidth: true
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            PlasmaComponents.Label { text: i18n("Brightness schedule") }
                            PlasmaComponents.Label {
                                Layout.fillWidth: true
                                opacity: 0.7
                                font: Kirigami.Theme.smallFont
                                elide: Text.ElideRight
                                text: !root.d ? "" : root.paused ? root.pausedText()
                                    : i18n("Next: %1% at %2", root.d.next.brightness, root.d.next.at)
                            }
                        }
                        PlasmaComponents.Switch {
                            checked: !root.paused
                            onToggled: root.run(checked ? "resume" : "pause forever")
                        }
                    }

                    Canvas {
                        id: graph
                        Layout.fillWidth: true
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 4
                        opacity: root.paused ? 0.5 : 1
                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.reset();
                            if (!root.d || !root.d.monitors.length) return;
                            var w = width, h = height;
                            var x = minute => minute / 1440 * w;
                            var y = pct => h - pct / 100 * h;

                            // Night: before sunrise and after sunset.
                            var rise = root.mins(root.d.sunrise), set = root.mins(root.d.sunset);
                            ctx.fillStyle = Qt.alpha(Kirigami.Theme.textColor, 0.07);
                            if (rise < set) {
                                ctx.fillRect(0, 0, x(rise), h);
                                ctx.fillRect(x(set), 0, w - x(set), h);
                            }
                            ctx.strokeStyle = Qt.alpha(Kirigami.Theme.textColor, 0.12);
                            ctx.lineWidth = 1;
                            [6, 12, 18].forEach(hr => {
                                ctx.beginPath();
                                ctx.moveTo(Math.round(x(hr * 60)) + 0.5, 0);
                                ctx.lineTo(Math.round(x(hr * 60)) + 0.5, h);
                                ctx.stroke();
                            });

                            var trace = v => {
                                ctx.beginPath();
                                for (var i = 0; i < v.length; i++) {
                                    var px = i * w / (v.length - 1);
                                    if (i === 0) ctx.moveTo(px, y(v[i])); else ctx.lineTo(px, y(v[i]));
                                }
                            };
                            var c = Kirigami.Theme.highlightColor;
                            var first = root.d.monitors[0].curve;
                            trace(first);
                            ctx.lineTo(w, h);
                            ctx.lineTo(0, h);
                            ctx.closePath();
                            var fill = ctx.createLinearGradient(0, 0, 0, h);
                            fill.addColorStop(0, Qt.alpha(c, 0.35));
                            fill.addColorStop(1, Qt.alpha(c, 0.02));
                            ctx.fillStyle = fill;
                            ctx.fill();
                            ctx.lineJoin = "round";
                            ctx.lineWidth = 2;
                            ctx.strokeStyle = c;
                            trace(first);
                            ctx.stroke();
                            // Other monitors only when their curve differs from the first.
                            root.d.monitors.slice(1).forEach(m => {
                                if (JSON.stringify(m.curve) === JSON.stringify(first)) return;
                                ctx.setLineDash([4, 3]);
                                ctx.lineWidth = 1.5;
                                ctx.strokeStyle = Qt.alpha(c, 0.7);
                                trace(m.curve);
                                ctx.stroke();
                                ctx.setLineDash([]);
                            });

                            var now = new Date();
                            var nm = now.getHours() * 60 + now.getMinutes();
                            var nv = first[Math.min(first.length - 1, Math.round(nm / 15))];
                            ctx.beginPath();
                            ctx.arc(x(nm), y(nv), 4, 0, 2 * Math.PI);
                            ctx.fillStyle = c;
                            ctx.fill();
                            ctx.lineWidth = 2;
                            ctx.strokeStyle = Kirigami.Theme.backgroundColor;
                            ctx.stroke();
                        }
                        Connections {
                            target: root
                            function onDChanged() { graph.requestPaint(); }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        opacity: 0.7
                        Kirigami.Icon {
                            source: "weather-clear"
                            Layout.preferredWidth: Kirigami.Units.iconSizes.small
                            Layout.preferredHeight: Kirigami.Units.iconSizes.small
                        }
                        PlasmaComponents.Label { text: root.d ? root.d.sunrise : ""; font: Kirigami.Theme.smallFont }
                        Item { Layout.fillWidth: true }
                        PlasmaComponents.Label { text: root.d ? root.d.sunset : ""; font: Kirigami.Theme.smallFont }
                        Kirigami.Icon {
                            source: "weather-clear-night"
                            Layout.preferredWidth: Kirigami.Units.iconSizes.small
                            Layout.preferredHeight: Kirigami.Units.iconSizes.small
                        }
                    }

                    RowLayout {
                        visible: root.draft === null
                        PlasmaComponents.Button {
                            icon.name: "configure"
                            text: i18n("Edit Schedule…")
                            onClicked: root.startEdit()
                        }
                        PlasmaComponents.Button {
                            visible: root.d !== null && root.d.edited
                            icon.name: "edit-reset"
                            text: i18n("Reset")
                            PlasmaComponents.ToolTip { text: i18n("Drop widget edits and use the IceDOS config again") }
                            onClicked: root.run("reset")
                        }
                    }

                    // Sunrise and sunset come from here.
                    RowLayout {
                        visible: root.draft !== null
                        Layout.fillWidth: true
                        PlasmaComponents.Label { text: i18n("Latitude") }
                        PlasmaComponents.TextField {
                            id: lat
                            Layout.fillWidth: true
                            placeholderText: i18n("e.g. 44.43")
                            text: root.draft ? String(root.draft.latitude) : ""
                            readonly property bool ok: /^-?\d+(\.\d+)?$/.test(text) && Math.abs(Number(text)) <= 90
                            color: ok ? Kirigami.Theme.textColor : Kirigami.Theme.negativeTextColor
                            onEditingFinished: if (ok && root.draft) root.draft.latitude = Number(text)
                        }
                        PlasmaComponents.Label { text: i18n("Longitude") }
                        PlasmaComponents.TextField {
                            id: lon
                            Layout.fillWidth: true
                            placeholderText: i18n("e.g. 26.10")
                            text: root.draft ? String(root.draft.longitude) : ""
                            readonly property bool ok: /^-?\d+(\.\d+)?$/.test(text) && Math.abs(Number(text)) <= 180
                            color: ok ? Kirigami.Theme.textColor : Kirigami.Theme.negativeTextColor
                            onEditingFinished: if (ok && root.draft) root.draft.longitude = Number(text)
                        }
                        Kirigami.ContextualHelpButton {
                            toolTipText: i18n("Latitude and longitude in decimal degrees, used for sunrise and sunset. North and east are positive, south and west negative.")
                        }
                    }

                    PointsEditor {
                        id: globalPoints
                        sunrise: root.d ? root.d.sunrise : ""
                        sunset: root.d ? root.d.sunset : ""
                        visible: root.draft !== null
                        Layout.fillWidth: true
                        points: root.draft ? root.draft.points : []
                        onPointsChanged: if (root.draft) root.draft.points = points
                    }

                    RowLayout {
                        visible: root.draft !== null
                        Layout.alignment: Qt.AlignRight
                        PlasmaComponents.Button {
                            text: i18n("Cancel")
                            icon.name: "dialog-cancel"
                            onClicked: root.draft = null
                        }
                        PlasmaComponents.Button {
                            text: i18n("Save")
                            icon.name: "document-save"
                            enabled: globalPoints.valid && lat.ok && lon.ok
                            onClicked: {
                                // Fields still focused haven't fired editingFinished yet.
                                root.draft.latitude = Number(lat.text);
                                root.draft.longitude = Number(lon.text);
                                root.saveEdit();
                            }
                        }
                    }
                }
            }
        }
    }
}
