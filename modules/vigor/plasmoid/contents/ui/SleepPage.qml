import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

Page {
    id: sleep
    required property var app

    readonly property var holds: app.s ? app.s.holds : null
    // Delay locks and key-handling locks (PowerDevil owns the power button) stay folded away by default.
    function major(i) { return i.mode === "block" && /idle|sleep|shutdown/.test(i.what); }
    readonly property var inhibitors: app.s ? app.s.inhibitors.filter(i => showMinor.checked || major(i)) : []
    readonly property int minorCount: app.s ? app.s.inhibitors.filter(i => !major(i)).length : 0
    readonly property var durations: [
        { text: i18n("Until off"), minutes: 0 },
        { text: i18n("15 min"), minutes: 15 },
        { text: i18n("30 min"), minutes: 30 },
        { text: i18n("1 hour"), minutes: 60 },
        { text: i18n("2 hours"), minutes: 120 },
        { text: i18n("4 hours"), minutes: 240 }
    ]
    readonly property int minutes: durations[duration.currentIndex].minutes
    readonly property var actions: [
        { id: "suspend", text: i18n("Sleep"), show: app.sm.canSuspend },
        { id: "hibernate", text: i18n("Hibernate"), show: app.sm.canHibernate },
        { id: "shutdown", text: i18n("Shut down"), show: app.sm.canShutdown },
        { id: "reboot", text: i18n("Restart"), show: app.sm.canReboot },
        { id: "logout", text: i18n("Log out"), show: app.sm.canLogout },
        { id: "lock", text: i18n("Lock"), show: app.sm.canLock }
    ].filter(a => a.show)

    function on(kind) { return holds !== null && holds[kind].on; }

    function until() {
        var t = ["idle", "sleep"].map(k => on(k) && holds[k].until).filter(x => x);
        if (!t.length) return "";
        return i18n("until %1", Qt.formatTime(new Date(Math.max.apply(null, t) * 1000), Qt.locale().timeFormat(Locale.ShortFormat)));
    }

    function actionName(id) {
        var a = actions.find(x => x.id === id);
        return a ? a.text : id;
    }

    // Inline components get no access to this file's ids, so the page comes in as a property.
    component HoldButton: PlasmaComponents.ToolButton {
        id: hb
        required property var page
        property var kinds: []
        property bool timed: true
        readonly property bool active: kinds.every(k => hb.page.on(k))
        Layout.fillWidth: true
        checkable: true
        checked: active
        enabled: page.holds !== null
        onClicked: {
            var want = !active;
            kinds.forEach(k => hb.page.app.hold(k, want, hb.timed ? hb.page.minutes : 0));
            // Clicking broke the binding; the next status read sets the real state.
            checked = Qt.binding(() => hb.active);
        }
    }

    component Section: PlasmaComponents.Label {
        font.bold: true
        opacity: 0.7
    }

    RowLayout {
        Layout.fillWidth: true
        Section { text: i18n("Keep awake"); Layout.fillWidth: true }
        PlasmaComponents.Label {
            text: sleep.until()
            opacity: 0.6
            font: Kirigami.Theme.smallFont
        }
        PlasmaComponents.ComboBox {
            id: duration
            model: sleep.durations
            textRole: "text"
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        HoldButton {
            page: sleep; kinds: ["idle"]
            icon.name: "preferences-desktop-screensaver"; text: i18n("Screen")
        }
        HoldButton {
            page: sleep; kinds: ["sleep"]
            icon.name: "system-suspend"; text: i18n("Sleep")
        }
        HoldButton {
            page: sleep; kinds: ["idle", "sleep"]
            icon.name: "system-suspend-inhibited"; text: i18n("Both")
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        HoldButton {
            page: sleep; kinds: ["dnd"]; timed: false
            icon.name: "notifications-disabled"; text: i18n("Do not disturb")
        }
        HoldButton {
            page: sleep; kinds: ["nightlight"]; timed: false
            icon.name: "redshift-status-off"; text: i18n("No Night Light")
        }
    }

    RowLayout {
        visible: sleep.app.pendingAction !== ""
        Layout.fillWidth: true
        Section { text: i18n("Scheduled") }
        PlasmaComponents.Label {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: i18n("%1 at %2, in %3", sleep.actionName(sleep.app.pendingAction),
                Qt.formatTime(new Date(sleep.app.pendingAt), Qt.locale().timeFormat(Locale.ShortFormat)),
                sleep.app.duration((sleep.app.pendingAt - sleep.app.now) / 1000))
        }
        PlasmaComponents.ToolButton {
            icon.name: "dialog-cancel"
            display: PlasmaComponents.AbstractButton.IconOnly
            text: i18n("Cancel")
            PlasmaComponents.ToolTip.text: text
            PlasmaComponents.ToolTip.visible: hovered
            onClicked: sleep.app.cancelSchedule()
        }
    }

    RowLayout {
        visible: sleep.app.pendingAction === ""
        Layout.fillWidth: true
        Section { text: i18n("Scheduled") }
        PlasmaComponents.ComboBox {
            id: what
            Layout.fillWidth: true
            model: sleep.actions
            textRole: "text"
        }
        QQC2.SpinBox {
            id: delay
            from: 1
            to: 1440
            value: 30
            editable: true
            textFromValue: v => i18n("%1 min", v)
            valueFromText: t => parseInt(t) || 1
        }
        PlasmaComponents.ToolButton {
            icon.name: "chronometer-start"
            display: PlasmaComponents.AbstractButton.IconOnly
            text: i18n("Start")
            PlasmaComponents.ToolTip.text: text
            PlasmaComponents.ToolTip.visible: hovered
            onClicked: sleep.app.schedule(sleep.actions[what.currentIndex].id, delay.value)
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Section { text: i18n("Inhibitors (%1)", sleep.inhibitors.length); Layout.fillWidth: true }
        PlasmaComponents.CheckBox {
            id: showMinor
            visible: sleep.minorCount > 0
            text: i18n("+%1 more", sleep.minorCount)
        }
    }

    PlasmaComponents.Label {
        visible: sleep.app.s !== null && sleep.inhibitors.length === 0
        opacity: 0.6
        text: i18n("Nothing is blocking sleep or the screen locker.")
    }

    // One line each; what, mode and source sit in the tooltip.
    Repeater {
        model: sleep.inhibitors
        delegate: RowLayout {
            required property var modelData
            Layout.fillWidth: true
            opacity: modelData.allowed ? 1 : 0.5

            PlasmaComponents.Label {
                Layout.fillWidth: true
                elide: Text.ElideRight
                textFormat: Text.StyledText
                text: "<b>" + modelData.who + "</b> " + modelData.why
                PlasmaComponents.ToolTip.text: [modelData.what.replace(/:/g, ", "), modelData.mode,
                    modelData.source === "plasma" ? "Plasma" : "logind",
                    modelData.pid ? "pid " + modelData.pid : "",
                    modelData.allowed ? "" : i18n("ignored")].filter(x => x).join(" · ")
                PlasmaComponents.ToolTip.visible: hover.hovered
                HoverHandler { id: hover }
            }
            // Plasma can ignore an app's request; logind locks can only be released by their owner.
            PlasmaComponents.ToolButton {
                visible: modelData.source === "plasma" && !modelData.ours
                icon.name: modelData.allowed ? "media-playback-pause" : "media-playback-start"
                display: PlasmaComponents.AbstractButton.IconOnly
                text: modelData.allowed ? i18n("Ignore this request") : i18n("Honor this request")
                PlasmaComponents.ToolTip.text: text
                PlasmaComponents.ToolTip.visible: hovered
                onClicked: sleep.app.run((modelData.allowed ? "block " : "allow ") + sleep.app.quote(modelData.who)
                    + " --why " + sleep.app.quote(modelData.why))
            }
        }
    }
}
