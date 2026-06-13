// Keyboard-layout OSD for focus-driven layout switches (KWin / Plasma 6, Wayland).
//
// WHY THIS EXISTS
// With per-window switching policy (kxkbrc SwitchMode=Window) focusing a
// different window silently switches the active layout. KDE only fires its
// native layout OSD on EXPLICIT switches (Meta+Space) -- focus-driven switches
// go through Policy::setLayout, which skips notifyLayoutChange, and no config
// key toggles it. This script restores the OSD for those silent switches.
//
// WHY POLLING (not windowActivated + getLayout)
// The per-window layout switch lands slightly AFTER workspace.windowActivated
// fires, so reading getLayout inside that handler returns the OUTGOING layout
// (classic off-by-one). KWin's callDBus is method-call-only and CANNOT
// subscribe to the org.kde.keyboard layoutChanged/layoutListChanged signals,
// and the KWin script API exposes no keyboard-layout signal at all. So we POLL
// getLayout (which reflects KWin's live current layout, already updated by the
// per-window policy) on a cheap repeating timer. On Meta+Space we harmlessly
// re-fire and merge into the native OSD. Cost: one trivial DBus call per tick.

const POLL_MS = 200;   // see icedos.nix note for making this configurable
const DEBUG   = false; // flip true to trace into the journal (journalctl --user -f)

// org.kde.keyboard surface (read current layout + the layout name table).
const KBD_SERVICE   = "org.kde.keyboard";
const KBD_PATH      = "/Layouts";
const KBD_INTERFACE = "org.kde.KeyboardLayouts";

// org.kde.plasmashell OSD service (shows the native layout OSD).
const OSD_SERVICE   = "org.kde.plasmashell";
const OSD_PATH      = "/org/kde/osdService";
const OSD_INTERFACE = "org.kde.osdService";

// getLayoutsList() returns a(sss) = [ [short, display, long], ... ].
// The native OSD shows the LONG name -> tuple field index [2]. (Verified live.)
const LONG_NAME_INDEX = 2;

let last     = null;  // last layout index SEEN; null until the first read seeds it
let inFlight = false; // guard: skip a tick while a DBus round-trip is still pending

function log() {
    if (!DEBUG) return;
    try {
        let s = "[layout-osd]";
        for (let i = 0; i < arguments.length; i++) s += " " + arguments[i];
        print(s);
    } catch (e) { /* print unavailable */ }
}

// callDBus is async; the callback receives the demarshalled return value(s).
// a(sss) arrives as a nested JS array (array of 3-string arrays).
function showOsdForIndex(idx) {
    callDBus(
        KBD_SERVICE, KBD_PATH, KBD_INTERFACE, "getLayoutsList",
        function (list) {
            if (!list || !list.length) { log("empty layout list"); return; }
            if (idx < 0 || idx >= list.length) {
                log("index", idx, "out of range of", list.length); return;
            }
            const tuple = list[idx];
            if (!tuple || tuple.length <= LONG_NAME_INDEX) {
                log("malformed tuple at", idx); return;
            }
            const longName = tuple[LONG_NAME_INDEX];
            log("OSD ->", longName, "(idx " + idx + ")");
            callDBus(OSD_SERVICE, OSD_PATH, OSD_INTERFACE,
                     "kbdLayoutChanged", longName);
        }
    );
}

function tick() {
    if (inFlight) return;           // don't stack round-trips if DBus is slow
    inFlight = true;
    callDBus(
        KBD_SERVICE, KBD_PATH, KBD_INTERFACE, "getLayout",
        function (idx) {
            inFlight = false;
            if (typeof idx !== "number") { log("bad getLayout:", idx); return; }
            if (idx === last) return;        // no change -> nothing to do

            const first = (last === null);
            last = idx;                       // persist BEFORE the async name fetch
            if (first) {                      // seed silently: no OSD on login/startup
                log("seed last =", idx);
                return;
            }
            showOsdForIndex(idx);
        }
    );
}

// One repeating QTimer (KWin JS has QTimer but NOT setTimeout). Same idiom as
// the dynamic-workspaces script. Fall back to a single seed read if QTimer is
// somehow unavailable.
try {
    const timer = new QTimer();
    timer.interval = POLL_MS;
    timer.singleShot = false;
    timer.timeout.connect(tick);
    timer.start();
    log("started, poll =", POLL_MS, "ms");
} catch (e) {
    log("QTimer unavailable:", e);
    tick(); // at least seed `last` once so a later manual reload behaves
}
