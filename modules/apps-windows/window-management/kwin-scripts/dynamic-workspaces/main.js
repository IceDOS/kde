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

const PER_SCREEN    = @PER_SCREEN@;  // injected from icedos perScreen
const MIN_DESKTOPS  = 2;             // one real desktop + one spare; never go below
const REMOVE_DELAY  = 200;           // ms to let other scripts drain before removing a desktop
const REMOVE_MAX_DELAY = 1000;       // window churn must never starve a removal past this
const DEBUG         = false;         // flip true to trace reconcile in the journal

let busy = false;                   // our own edits re-fire signals -> guard recursion

let reconcileTimer = null;          // defer pool edits out of the signal emit
let removeTimer = null;             // deferred desktop removal (see applyRemovals)
let removalsPending = false;        // sync-fallback intent; drained by reconcile()/applyRemovals
let removeDeadline = 0;             // ms-epoch cap set on first request; cleared on apply
function scheduleReconcile() {
    try {
        if (reconcileTimer === null) {
            reconcileTimer = new QTimer();
            reconcileTimer.singleShot = true;
            reconcileTimer.interval = 0;
            reconcileTimer.timeout.connect(reconcile);
        }
        reconcileTimer.start(0);    // restart coalesces signal bursts
    } catch (e) {
        log("QTimer unavailable, running sync:", e);
        reconcile();
    }
}

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
    return PER_SCREEN && !!(workspace.screens && workspace.screens.length);
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
    catch (e) { /* no per-output view API; leave each output's view as-is */ }
}

// Normal, non-sticky, single-desktop, pager-visible window (minimized still counts).
function packable(w) {
    return w && !w.skipPager && !w.onAllDesktops &&
        w.desktops && w.desktops.length === 1;
}

function onOutput(w, output) {
    if (output === null) return true;
    try {
        const o = w.output;
        if (o) return o === output || (o.name && o.name === output.name);
        // No output set (window on a non-viewed desktop): match by geometry.
        const g = w.frameGeometry, r = output.geometry;
        const cx = g.x + g.width / 2, cy = g.y + g.height / 2;
        return cx >= r.x && cx < r.x + r.width && cy >= r.y && cy < r.y + r.height;
    } catch (e) { return false; }
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

// Desktops eligible for removal: empty on all outputs, not currently viewed by
// any output, never the trailing spare, and above the minimum count.
function removableDesktops() {
    if (desktops().length <= MIN_DESKTOPS) return [];
    const inUse = inUseDesktops();
    const last = desktops()[desktops().length - 1];
    return desktops().slice().filter(d =>
        inUse.indexOf(d) === -1 && d !== last && isEmpty(d));
}

function scheduleRemovals() {
    try {
        if (removeTimer === null) {
            removeTimer = new QTimer();
            removeTimer.singleShot = true;
            removeTimer.interval = 0;
            removeTimer.timeout.connect(applyRemovals);
        }
        const now = Date.now();
        if (removeDeadline === 0) removeDeadline = now + REMOVE_MAX_DELAY;
        removeTimer.start(Math.max(0, Math.min(REMOVE_DELAY, removeDeadline - now)));
    } catch (e) {
        log("QTimer unavailable, removals pending:", e);
        removalsPending = true;     // reconcile()'s finally drains it after busy clears
    }
}

// Removing a desktop destroys its object. Other KWin scripts (Polonium) may
// still hold that desktop in a queued desktopsChanged event; if it is destroyed
// before they process it, the window drops out of tiling and ends up floating.
// Defer removals until the event queues have drained.
function applyRemovals() {
    if (busy) { removalsPending = true; return; }  // reconcile's finally drains it
    removeDeadline = 0;
    removalsPending = false;
    busy = true;
    let removed = 0;
    try {
        removableDesktops().forEach(d => {
            if (desktops().length <= MIN_DESKTOPS) return;   // re-check floor per removal
            try { workspace.removeDesktop(d); removed++; }
            catch (e) { log("remove failed:", e); }
        });
    } finally {
        busy = false;
    }
    if (removed > 0) scheduleReconcile();   // after busy clears, so the sync fallback isn't swallowed
}

function reconcile() {
    if (busy) return;
    busy = true;
    try {
        if (hasPerOutput()) {
            try { compactOutputs(desktops()); }
            catch (e) { log("compaction error, global-only:", e); }
        }

        if (removableDesktops().length) scheduleRemovals();

        let all = desktops();
        if (!isEmpty(all[all.length - 1])) {
            workspace.createDesktop(all.length, "Desktop " + (all.length + 1));
        }

        all = desktops();
        for (let i = 0; i < all.length; i++) {
            const want = "Desktop " + (i + 1);
            if (all[i].name !== want) all[i].name = want;
        }

        if (DEBUG) log("pending removals=" + removableDesktops().length +
            " count=" + desktops().length);
    } finally {
        busy = false;
        // Only the QTimer-failure path, a defensive busy-guard hit, or an
        // elapsed deadline lands here; it bypasses REMOVE_DELAY by design —
        // everything is already degraded.
        if (removalsPending) {
            try { applyRemovals(); }
            catch (e) { log("removal drain failed:", e); }
        }
    }
}

function watch(w) { if (w) w.desktopsChanged.connect(scheduleReconcile); }

workspace.windowList().forEach(watch);
workspace.windowAdded.connect(w => { watch(w); scheduleReconcile(); });
workspace.windowRemoved.connect(scheduleReconcile);
workspace.currentDesktopChanged.connect(scheduleReconcile);

scheduleReconcile();
