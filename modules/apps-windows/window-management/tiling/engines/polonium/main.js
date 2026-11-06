const GAP = @GAP@;
const MAX_RETRIES = 20;

let applyTimer = null;
let retries = 0;

function logConnectError(e) {
    try { print("[gap-pin] connect failed: " + e); } catch (e2) { }
}

function scheduleApply(delay) {
    try {
        if (applyTimer === null) {
            const t = new QTimer();
            t.singleShot = true;
            t.interval = 0;
            t.timeout.connect(applyPadding);
            applyTimer = t;
        }
        applyTimer.start(delay || 0);
    } catch (e) {
        applyPadding();
    }
}

function onSignal() {
    retries = 0;
    scheduleApply(0);
}

function applyPadding() {
    let missing = false;
    const desktops = workspace.desktops;
    const screens = workspace.screens;
    for (let i = 0; i < screens.length; i++) {
        for (let j = 0; j < desktops.length; j++) {
            const root = workspace.rootTile(screens[i], desktops[j]);
            if (root) {
                if (root.padding !== GAP) {
                    root.padding = GAP;
                }
            } else {
                missing = true;
            }
        }
    }
    if (missing) {
        if (retries++ < MAX_RETRIES) {
            scheduleApply(250);
        }
    } else {
        retries = 0;
    }
}

scheduleApply(0);

try { workspace.desktopsChanged.connect(onSignal); } catch (e) { logConnectError(e); }
try { workspace.currentDesktopChanged.connect(onSignal); } catch (e) { logConnectError(e); }
try { workspace.screensChanged.connect(onSignal); } catch (e) { logConnectError(e); }
try { workspace.windowAdded.connect(onSignal); } catch (e) { logConnectError(e); }
