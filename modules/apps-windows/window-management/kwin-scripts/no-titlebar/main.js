// IceDOS no-titlebar (KWin / Plasma 6, Wayland).
//
// Strips the server-side titlebar/decoration from every normal, managed
// top-level window by setting `noBorder` (the same property Krohnkite toggles
// when tiling). Client-side-decorated apps (GTK/Electron) draw their own bar and
// report no server decoration, so `noBorder` is a harmless no-op for them.

const EXCLUDE = @EXCLUDE_CLASSES@; // injected from icedos excludeClasses

function excluded(w) {
    const rc = (w.resourceClass || "").toString().toLowerCase();
    return EXCLUDE.some(function (e) {
        return e && rc.indexOf(e.toLowerCase()) !== -1;
    });
}

function apply(w) {
    if (!w || !w.normalWindow || !w.managed) return;
    if (w.specialWindow || w.dock || w.desktopWindow || w.transient) return;
    if (excluded(w)) return;
    w.noBorder = true;
}

workspace.windowList().forEach(apply);
workspace.windowAdded.connect(apply);
