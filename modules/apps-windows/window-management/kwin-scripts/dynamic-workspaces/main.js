// Per-monitor dynamic virtual desktops (KWin / Plasma 6.7, Wayland).
//
// KWin desktops are a single GLOBAL ordered pool. With PerOutputVirtualDesktops
// each monitor independently views one global desktop, and the same global
// desktop shows different windows per output. To make every monitor behave like
// its own left-packed dynamic-workspace stack we MOVE each output's windows down
// onto the lowest desktops (closing that output's gaps), then trim desktops that
// are empty on ALL outputs, keeping one trailing empty. Falls back to a single
// global stack when per-output desktops are off.
//
// Middle-removal / animation-safe technique adapted from
// maurges/dynamic_workspaces (BSD-3-Clause).

const PER_SCREEN   = @PER_SCREEN@;  // injected from icedos perScreen
const MIN_DESKTOPS = 2;             // one real desktop + one spare; never go below
const DEBUG        = false;         // flip true to trace reconcile in the journal

let busy = false;                   // our own edits re-fire signals -> guard recursion

function log() {
    if (!DEBUG) return;
    try {
        let s = "[dyn-ws]";
        for (let i = 0; i < arguments.length; i++) s += " " + arguments[i];
        print(s);
    } catch (e) { /* print unavailable */ }
}

function desktops() { return workspace.desktops; }

function hasPerOutput() {
    return PER_SCREEN &&
        typeof workspace.currentDesktopForScreen === "function" &&
        typeof workspace.setCurrentDesktopForScreen === "function" &&
        !!(workspace.screens && workspace.screens.length);
}

function currentDesktopOf(output) {
    if (output === null) return workspace.currentDesktop;
    try { return workspace.currentDesktopForScreen(output); }
    catch (e) { return workspace.currentDesktop; }
}

function setCurrentDesktopOf(output, vd) {
    if (!vd) return;
    if (output === null) { workspace.currentDesktop = vd; return; }
    try { workspace.setCurrentDesktopForScreen(vd, output); }
    catch (e) { workspace.currentDesktop = vd; }
}

// Normal, non-sticky, single-desktop, pager-visible window (minimized still counts).
function packable(w) {
    return w && !w.skipPager && !w.onAllDesktops &&
        w.desktops && w.desktops.length === 1;
}

function onOutput(w, output) {
    if (output === null) return true;
    try { return w.output === output; } catch (e) { return false; }
}

// Global emptiness: no packable window references this desktop on ANY output.
function isEmpty(desktop) {
    return !workspace.windowList().some(w =>
        packable(w) && w.desktops.indexOf(desktop) !== -1);
}

// Ordered global desktops holding >=1 packable window of `output`.
function occupiedDesktopsFor(output, all) {
    const wins = workspace.windowList().filter(w => packable(w) && onOutput(w, output));
    const occ = [];
    for (let i = 0; i < all.length; i++) {
        const d = all[i];
        if (occ.indexOf(d) === -1 && wins.some(w => w.desktops.indexOf(d) !== -1)) occ.push(d);
    }
    return occ;
}

function moveGroup(output, from, to) {
    if (from === to) return 0;
    let moved = 0;
    workspace.windowList().forEach(w => {
        if (packable(w) && onOutput(w, output) && w.desktops.indexOf(from) !== -1) {
            try { w.desktops = [to]; moved++; } catch (e) { log("move failed:", e); }
        }
    });
    return moved;
}

// Per-output left-compaction + keep each output looking at the same content.
function compactOutputs(all) {
    workspace.screens.slice().forEach(output => {
        const occ = occupiedDesktopsFor(output, all);
        if (!occ.length) return;
        const viewedOcc = occ.indexOf(currentDesktopOf(output));
        for (let k = 0; k < occ.length; k++) moveGroup(output, occ[k], all[k]);
        if (viewedOcc !== -1) setCurrentDesktopOf(output, all[viewedOcc]);
        log("output", output ? output.name : "?", "occ", occ.length, "viewed", viewedOcc);
    });
}

// Desktops any output currently views -> never remove.
function inUseDesktops() {
    const inUse = [];
    const push = d => { if (d && inUse.indexOf(d) === -1) inUse.push(d); };
    push(workspace.currentDesktop);
    if (hasPerOutput()) workspace.screens.slice().forEach(o => push(currentDesktopOf(o)));
    return inUse;
}

function reconcile() {
    if (busy) return;
    busy = true;
    try {
        if (hasPerOutput()) {
            try { compactOutputs(desktops()); }
            catch (e) { log("compaction error, global-only:", e); }
        }

        const inUse = inUseDesktops();
        const last = desktops()[desktops().length - 1];   // trailing spare
        const removed = [];
        desktops().slice().forEach(d => {
            if (inUse.indexOf(d) === -1 && d !== last &&
                isEmpty(d) && desktops().length > MIN_DESKTOPS) {
                removed.push(d.name);
                workspace.removeDesktop(d);
            }
        });

        let all = desktops();
        if (!isEmpty(all[all.length - 1])) {
            workspace.createDesktop(all.length, "Desktop " + (all.length + 1));
        }

        all = desktops();
        for (let i = 0; i < all.length; i++) {
            const want = "Desktop " + (i + 1);
            if (all[i].name !== want) all[i].name = want;
        }

        if (DEBUG) log("removed=[" + removed.join(",") + "] count=" + desktops().length);
    } finally {
        busy = false;
    }
}

function watch(w) { if (w) w.desktopsChanged.connect(reconcile); }

workspace.windowList().forEach(watch);
workspace.windowAdded.connect(w => { watch(w); reconcile(); });
workspace.windowRemoved.connect(reconcile);
workspace.currentDesktopChanged.connect(reconcile);

reconcile();
