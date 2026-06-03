function moveToDesktopAndFollow(index) {
    const win = workspace.activeWindow;
    if (!win) return;
    const desktops = workspace.desktops;
    if (index < 1 || index > desktops.length) return; // no such desktop -> no-op
    const target = desktops[index - 1];
    win.desktops = [target];
    workspace.currentDesktop = target; // follow
}

for (let i = 1; i <= 10; i++) {
    registerShortcut(
        "MoveWindowToDesktopAndFollow" + i,
        "Move Window to Desktop " + i + " and Follow",
        "", // key bound via config.toml (plasma-manager), same as Krohnkite
        () => moveToDesktopAndFollow(i)
    );
}
