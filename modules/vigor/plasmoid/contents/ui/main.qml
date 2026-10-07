import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.private.sessions as Sessions

PlasmoidItem {
    id: root

    property var d: null
    property string lastError: ""
    // Session-side state from `vigor ctl status`: profile, devices, inhibitors, holds.
    property var s: null
    // The tray gives each item a square cell, so text there would spill over its neighbours.
    readonly property bool inTray: (Plasmoid.containmentDisplayHints & PlasmaCore.Types.ContainmentForcesSquarePlasmoids) !== 0
    // Hidden until a local-model request has been metered at least once.
    readonly property var ai: d && d.ai && d.ai.all.wh > 0 ? d.ai : null
    readonly property bool holding: s !== null && (s.holds.idle.on || s.holds.sleep.on)

    // Replaced with store paths at build time (icedos.nix).
    readonly property string readCmd: "@cat@ @now@"
    readonly property string ctl: "@vigor@ ctl"

    readonly property var labels: ({
        cpu: i18n("CPU"), gpu: i18n("GPU"), disk: i18n("Disks"), network: i18n("Network"),
        board: i18n("Board, RAM, fans"), psu: i18n("PSU loss"),
        extra: i18n("Other loads"), standby: i18n("Standby")
    })

    // Scheduled power action; kept in the applet config so a plasmashell restart keeps it.
    readonly property string pendingAction: Plasmoid.configuration.pendingAction
    readonly property real pendingAt: Number(Plasmoid.configuration.pendingAt) || 0
    property real now: Date.now()

    function money(v) {
        if (!d || v === undefined) return "-";
        return d.currency + v.toFixed(v < 1 ? 3 : 2);
    }

    function rate(bps) {
        var u = ["B/s", "KiB/s", "MiB/s", "GiB/s"], i = 0;
        while (bps >= 1024 && i < u.length - 1) { bps /= 1024; i++; }
        return bps.toFixed(i ? 1 : 0) + " " + u[i];
    }

    function duration(sec) {
        sec = Math.max(0, Math.round(sec));
        var h = Math.floor(sec / 3600), m = Math.floor(sec % 3600 / 60);
        if (h > 0) return i18n("%1 h %2 min", h, m);
        if (m > 0) return i18n("%1 min", m);
        return i18n("%1 s", sec);
    }

    function stale() {
        return !d || (Date.now() / 1000 - d.ts) > d.interval * 5;
    }

    // The window the per-component costs use (componentWindow in icedos.nix).
    function compWindow() {
        if (!d) return null;
        return d.windows.find(w => w.label === d.component_window) || d.windows[0];
    }

    function componentCost(c) {
        var w = compWindow();
        return w && w.by[c] ? w.by[c].cost : 0;
    }

    function quote(v) {
        return "'" + String(v).replace(/'/g, "'\\''") + "'";
    }

    // Run a ctl subcommand, then refresh the session state so the UI shows the result.
    function run(args) {
        action.connectSource(ctl + " " + args);
    }

    function hold(kind, on, minutes) {
        run(on ? "hold " + kind + " --minutes " + (minutes || 0) : "release " + kind);
    }

    function schedule(what, minutes) {
        Plasmoid.configuration.pendingAction = what;
        Plasmoid.configuration.pendingAt = String(Date.now() + minutes * 60000);
    }

    function cancelSchedule() {
        Plasmoid.configuration.pendingAction = "";
        Plasmoid.configuration.pendingAt = "0";
    }

    function perform(what) {
        switch (what) {
        case "lock": sm.lock(); break;
        case "switch": sm.switchUser(); break;
        case "logout": sm.requestLogout(); break;
        case "suspend": sm.suspend(); break;
        case "hibernate": sm.hibernate(); break;
        case "reboot": sm.requestReboot(); break;
        case "shutdown": sm.requestShutdown(); break;
        case "firmware": run("firmware"); break;
        }
    }

    Sessions.SessionManagement { id: sessionManager }
    readonly property alias sm: sessionManager

    Plasmoid.icon: Qt.resolvedUrl("../icons/vigor.svg").toString().replace("file://", "")
    toolTipMainText: d ? Math.round(d.total_w) + " W" : "vigor"
    toolTipSubText: {
        var lines = [];
        if (d && compWindow()) lines.push(i18n("%1/h, %2 %3", money(d.cost_per_hour), compWindow().label, money(compWindow().cost)));
        else if (lastError) lines.push(lastError);
        if (holding) lines.push(i18n("Keeping the computer awake"));
        if (pendingAction) lines.push(i18n("%1 in %2", pendingAction, duration((pendingAt - now) / 1000)));
        return lines.join("\n");
    }

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            if (data["exit code"] !== 0) {
                root.d = null;
                root.lastError = i18n("vigor service is not running");
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

    P5Support.DataSource {
        id: status
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            try {
                if (data["exit code"] === 0) root.s = JSON.parse(data.stdout);
            } catch (e) {
                console.warn("vigor ctl status:", e);
            }
        }
    }

    P5Support.DataSource {
        id: action
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            if (data["exit code"] !== 0) console.warn("vigor:", source, data.stderr);
            status.connectSource(root.ctl + " status");
        }
    }

    Timer {
        interval: Math.max(1, Plasmoid.configuration.refreshSec) * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: exec.connectSource(root.readCmd)
    }

    // Session state changes rarely; poll it fast only while the popup is open.
    Timer {
        interval: root.expanded ? 3000 : 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: status.connectSource(root.ctl + " status")
    }

    Timer {
        interval: 1000
        running: root.pendingAction !== "" || root.expanded
        repeat: true
        onTriggered: {
            root.now = Date.now();
            if (root.pendingAction && root.now >= root.pendingAt) {
                var what = root.pendingAction;
                root.cancelSchedule();
                // A logout or shutdown that waits on a prompt would defeat the timer.
                if (what === "shutdown") sm.requestShutdown(Sessions.SessionManagement.ConfirmationMode.Skip);
                else if (what === "reboot") sm.requestReboot(Sessions.SessionManagement.ConfirmationMode.Skip);
                else if (what === "logout") sm.requestLogout(Sessions.SessionManagement.ConfirmationMode.Skip);
                else root.perform(what);
            }
        }
    }

    compactRepresentation: MouseArea {
        Layout.minimumWidth: root.inTray ? -1 : row.implicitWidth
        onClicked: root.expanded = !root.expanded

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
                opacity: root.stale() ? 0.5 : 1

                // A badge while a hold or a scheduled action is pending.
                Kirigami.Icon {
                    visible: root.holding || root.pendingAction !== ""
                    source: root.pendingAction !== "" ? "chronometer" : "system-suspend-inhibited"
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    width: parent.width * 0.5
                    height: width
                }
            }
            PlasmaComponents.Label {
                visible: !root.inTray && Plasmoid.configuration.showWatts && root.d !== null
                text: root.d ? Math.round(root.d.total_w) + " W" : ""
            }
            PlasmaComponents.Label {
                visible: !root.inTray && Plasmoid.configuration.showCost && root.d !== null
                text: root.d ? root.money(root.d.cost_per_hour) + "/h" : ""
                opacity: 0.7
            }
        }
    }

    fullRepresentation: ColumnLayout {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 25
        // Fits the open tab, so short tabs don't leave an empty popup; long ones scroll.
        Layout.preferredHeight: Math.min(tabs.implicitHeight + pages.children[pages.currentIndex].contentHeight + footer.implicitHeight,
                                         Kirigami.Units.gridUnit * 32)
        Layout.minimumWidth: Kirigami.Units.gridUnit * 20
        Layout.minimumHeight: Kirigami.Units.gridUnit * 10
        spacing: 0

        PlasmaComponents.TabBar {
            id: tabs
            Layout.fillWidth: true
            currentIndex: Plasmoid.configuration.lastTab
            onCurrentIndexChanged: Plasmoid.configuration.lastTab = currentIndex

            PlasmaComponents.TabButton { text: i18n("Meter") }
            PlasmaComponents.TabButton { text: i18n("Performance") }
            PlasmaComponents.TabButton { text: i18n("Devices") }
            PlasmaComponents.TabButton { text: i18n("Sleep") }
        }

        StackLayout {
            id: pages
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabs.currentIndex

            MeterPage { app: root }
            PerformancePage { app: root }
            DevicesPage { app: root }
            SleepPage { app: root }
        }

        PowerBar {
            id: footer
            app: root
            Layout.fillWidth: true
        }
    }
}
