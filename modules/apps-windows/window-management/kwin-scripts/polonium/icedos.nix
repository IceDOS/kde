{ icedosLib, lib, ... }:

{
  options.icedos.desktop.kde.polonium =
    let
      inherit (icedosLib) mkEnumOption mkIntBetweenOption;
      inherit (lib) importTOML;

      inherit ((importTOML ./config.toml).icedos.desktop.kde.polonium)
        defaultEngine
        borders
        tileResizeAmount
        btreeInsertionStyle
        gap
        ;
    in
    {
      defaultEngine =
        mkEnumOption
          {
            path = "icedos.desktop.kde.polonium.defaultEngine";
            source = ./config.toml;
            default = defaultEngine;
          }
          [
            "BTree"
            "Half"
            "ThreeColumn"
            "Pillars"
            "Pager"
            "KWin"
          ];

      borders =
        mkEnumOption
          {
            path = "icedos.desktop.kde.polonium.borders";
            source = ./config.toml;
            default = borders;
          }
          [
            "None"
            "Floating"
            "Active"
            "FloatingActive"
            "All"
          ];

      tileResizeAmount = mkIntBetweenOption {
        path = "icedos.desktop.kde.polonium.tileResizeAmount";
        source = ./config.toml;
        default = tileResizeAmount;
      } 1 1000;

      btreeInsertionStyle =
        mkEnumOption
          {
            path = "icedos.desktop.kde.polonium.btreeInsertionStyle";
            source = ./config.toml;
            default = btreeInsertionStyle;
          }
          [
            "Shallow"
            "Dwindle"
            "Spiral"
          ];

      gap = mkIntBetweenOption {
        path = "icedos.desktop.kde.polonium.gap";
        source = ./config.toml;
        default = gap;
      } 0 100;
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        {
          config,
          pkgs,
          ...
        }:
        let
          inherit (config.icedos.desktop.kde.polonium)
            defaultEngine
            borders
            tileResizeAmount
            btreeInsertionStyle
            gap
            ;

          engineMap = {
            BTree = 0;
            Half = 1;
            ThreeColumn = 2;
            Pillars = 3;
            Pager = 4;
            KWin = 5;
          };
          bordersMap = {
            None = 0;
            Floating = 1;
            Active = 2;
            FloatingActive = 3;
            All = 4;
          };
          insertionMap = {
            Shallow = 0;
            Dwindle = 1;
            Spiral = 2;
          };

          # KWin only re-reads tiling padding when a desktop's RootTile is
          # created (desktopAdded) and deletes the bare [Tiling].padding
          # fallback, so desktops created at runtime (dynamic-workspaces-omni
          # gives each a fresh UUID) fall back to the hardcoded 4px padding.
          # Pin rootTile.padding live via a KWin script so both the runtime
          # layout and the saved config stay at `gap`.
          gapPinner =
            pkgs.runCommandLocal "kwin-icedos-gap-pin"
              {
                meta = {
                  description = "IceDOS KWin script pinning rootTile padding";
                  license = lib.licenses.mit;
                };
              }
              ''
                dir="$out/share/kwin/scripts/icedos-gap-pin"
                mkdir -p "$dir/contents/code"
                cp ${./metadata.json} "$dir/metadata.json"
                cp ${
                  pkgs.replaceVars ./main.js {
                    GAP = toString gap;
                  }
                } "$dir/contents/code/main.js"
              '';

          # IceDOS polonium patches, applied unconditionally on top of stock
          # polonium 1.2.1 (the Half-engine phantom-window bug below is stock
          # polonium, not specific to dynamic-workspaces):
          #
          # 1. evUpdateWindow (dynamic-workspaces race): when the desktop a
          #    window just left is removed before Polonium processes its queued
          #    desktopsChanged event (our dynamic-workspaces script defers
          #    removals, but any desktop churn can race), getDriver() can't
          #    resolve the old display because the desktop object is gone —
          #    either its QObject is destroyed (desktop.id is undefined) or it
          #    has been dropped from the live workspace.desktops list — and
          #    Polonium silently untiles the moved window. Only in that case do
          #    we assume the window was tiled — gated on the handler's own
          #    wantsTiled so genuinely floating windows are never force-tiled
          #    — and it stays tiled on the new desktop.
          #
          # 2. Half-engine phantom window (stock polonium): BTreeEngine guards
          #    duplicate adds with windowSet, but HalfEngine has no equivalent
          #    — tileWindow, placeWindow and placeWindowPoint can all reach
          #    engine.addWindow while the window is already tiled, and
          #    HalfEngine.placeWindow calls addWindow for any tile it does not
          #    know (e.g. a stale persisted kwin tile). A second box for the
          #    same window renders as an EMPTY tile: KWin can only manage a
          #    window into one tile, the other box stays boxed but windowless,
          #    permanently hogging space. The windowMap-side prune in
          #    buildLayout cannot see it (the engine window still maps to a
          #    live kwin window), removeWindow only splices the first box, and
          #    KWin persists the empty tile in kwinrc, so the phantom survives
          #    reloads and reboots. Fix: skip duplicate adds, remove the window
          #    from both sides, and self-heal orphans/duplicates during
          #    buildLayout. Drop this patch if/once fixed upstream;
          #    --replace-fail breaks the build loudly if a polonium bump
          #    reshapes a block.
          poloniumPatchOld = "      const driver = this.getDriver(oldDisplay);\n      if (driver === void 0) {\n        continue;\n      }\n      if (driver.isWindowTiled(window)) {\n        tiled = true;\n      }";
          poloniumPatchNew = "      const driver = this.getDriver(oldDisplay);\n      if (driver === void 0) {\n        if ((oldDisplay.desktop?.id === void 0 || !this.workspace.desktops.includes(oldDisplay.desktop)) && this.windowHandlers.get(window)?.wantsTiled) {\n          tiled = true;\n        }\n        continue;\n      }\n      if (driver.isWindowTiled(window)) {\n        tiled = true;\n      }";
          halfAddWindowOld = "  addWindow(window, tile, direction) {\n    if (this.settings.insertInActive && tile !== void 0) {\n      this.placeWindow(window, tile, direction);\n      return;\n    }\n    if (!this.settings.swapInsertSide) {";
          halfAddWindowNew = "  addWindow(window, tile, direction) {\n    if (this.settings.insertInActive && tile !== void 0) {\n      this.placeWindow(window, tile, direction);\n      return;\n    }\n    // IceDOS fix: never let one window occupy two boxes of the Half engine.\n    // BTreeEngine guards with windowSet; HalfEngine has no equivalent, so any\n    // unguarded add (tileWindow, placeWindow and placeWindowPoint all reach\n    // engine.addWindow while the window is already tiled) created a second box\n    // for the same window. KWin can only manage a window into one tile, so the\n    // extra box rendered as an empty tile that permanently hogged space: the\n    // phantom window. Skip the add instead. (HalfEngine.placeWindow can still\n    // splice a duplicate directly when its tileMap scan misses a stale box;\n    // the buildLayout self-heal collapses that case on the next rebuild.)\n    if (\n      this.side1.some((x) => x.window == window) ||\n      this.side2.some((x) => x.window == window)\n    ) {\n      console().debug(\"window already tiled in half engine, skipping duplicate add\");\n      return;\n    }\n    if (!this.settings.swapInsertSide) {";
          halfRemoveWindowOld = "  removeWindow(window) {\n    let [side, otherSide] = this.side1.some((x) => x.window == window) ? [this.side1, this.side2] : [this.side2, this.side1];\n    let idx = side.findIndex((x) => x.window == window);\n    if (idx == -1) {\n      return;\n    }\n    side.splice(idx, 1);\n    if (side.length == 0 && otherSide.length > 1) {\n      side.push(otherSide.splice(0, 1)[0]);\n    }\n  }";
          halfRemoveWindowNew = "  removeWindow(window) {\n    // IceDOS fix: remove the window from both sides, not just the first side\n    // stock looked at. A duplicated window (see addWindow guard) otherwise\n    // kept a box forever: untile removed only one box, so the phantom tile\n    // survived any amount of window closing or retiling until the engine was\n    // rebuilt empty. The addWindow guard makes new duplicates impossible;\n    // a duplicate created before this fix is collapsed by the buildLayout\n    // self-heal on the rebuild after it appears (all boxes removed, one\n    // re-added), so an untile only ever sees a single box. For a window that\n    // closed, any leftover box is an orphan the same prune removes. The\n    // rebalance is keyed off the first side that held the window (side1\n    // priority, matching stock), so non-duplicate removals behave exactly as\n    // stock did.\n    const idx1 = this.side1.findIndex((x) => x.window == window);\n    const idx2 = this.side2.findIndex((x) => x.window == window);\n    if (idx1 == -1 && idx2 == -1) {\n      return;\n    }\n    if (idx1 != -1) {\n      this.side1.splice(idx1, 1);\n    }\n    if (idx2 != -1) {\n      this.side2.splice(idx2, 1);\n    }\n    if (idx1 != -1) {\n      if (this.side1.length == 0 && this.side2.length > 1) {\n        this.side1.push(this.side2.splice(0, 1)[0]);\n      }\n    } else if (this.side2.length == 0 && this.side1.length > 1) {\n      this.side2.push(this.side1.splice(0, 1)[0]);\n    }\n  }";
          buildLayoutSelfHealOld = "    this.engineRootTile = this.tilingEngine.buildLayout();\n    this.tileMap = buildLayout(rootTile, this.engineRootTile);";
          buildLayoutSelfHealNew = "    this.engineRootTile = this.tilingEngine.buildLayout();\n    this.tileMap = buildLayout(rootTile, this.engineRootTile);\n    // IceDOS self-heal: prune engine windows no kwin window maps to\n    // (orphans, e.g. left behind when a desktop was removed while a\n    // desktopsChanged event was queued) and — for the Half engine only —\n    // collapse duplicate boxes for the same window (the phantom: one window in\n    // two boxes renders as an empty tile that permanently hogged space). The\n    // existing windowMap-side prune below cannot see either case, because both\n    // engine windows still map to a live kwin window. Dup collapse is gated on\n    // the Half engine because only it got the matching addWindow guard and\n    // all-boxes removeWindow: ThreeColumn/Pillars/Pager remove one box per call\n    // and lack the guard, so remove+add would reshuffle the layout every\n    // rebuild without converging; KwinEngine.addWindow is a no-op, so the\n    // window would be silently untiled. Orphan pruning is safe for all engines.\n    const invWindowMap = new Map(Array.from(this.windowMap, (a) => [a[1], a[0]]));\n    const seenEngineWindows = new Set();\n    const orphanWindows = new Set();\n    const dupWindows = new Set();\n    const engineStack = [this.engineRootTile];\n    while (engineStack.length > 0) {\n      const engineTile = engineStack.pop();\n      for (const engineWindow of engineTile.windows) {\n        if (!invWindowMap.has(engineWindow)) {\n          orphanWindows.add(engineWindow);\n        } else if (seenEngineWindows.has(engineWindow)) {\n          dupWindows.add(engineWindow);\n        } else {\n          seenEngineWindows.add(engineWindow);\n        }\n      }\n      for (const child of engineTile.children) {\n        engineStack.push(child);\n      }\n    }\n    const collapseDups = this.tilingEngine.engineType === 1 /* Half */ && dupWindows.size > 0;\n    if (orphanWindows.size > 0 || collapseDups) {\n      console().warn(\n        \"pruning\",\n        orphanWindows.size,\n        \"orphaned and\",\n        collapseDups ? dupWindows.size : 0,\n        \"duplicated engine windows\"\n      );\n      for (const engineWindow of orphanWindows) {\n        this.tilingEngine.removeWindow(engineWindow);\n      }\n      if (collapseDups) {\n        for (const engineWindow of dupWindows) {\n          this.tilingEngine.removeWindow(engineWindow);\n          this.tilingEngine.addWindow(engineWindow);\n        }\n      }\n      // Rebuild once so the healed engine reaches the kwin tree. Safe because\n      // Controller.queueEvent drops events while processingEvents is true; a\n      // future event-loop refactor must keep that guarantee or this becomes a\n      // rebuild loop.\n      this.engineRootTile = this.tilingEngine.buildLayout();\n      this.tileMap = buildLayout(rootTile, this.engineRootTile);\n    }";

          poloniumPatched =
            pkgs.runCommandLocal "polonium-icedos"
              {
                meta = {
                  description = "Polonium with fixes for windows floating after cross-desktop moves and the Half-engine phantom-window bug";
                  homepage = "https://polonium.vaughanm.xyz/";
                  license = lib.licenses.mit;
                };
              }
              ''
                mkdir -p "$out"
                cp -r ${pkgs.polonium}/. "$out/"
                chmod -R u+w "$out"
                substituteInPlace "$out/share/kwin/scripts/polonium/contents/code/main.mjs" \
                  --replace-fail '${poloniumPatchOld}' '${poloniumPatchNew}' \
                  --replace-fail '${halfAddWindowOld}' '${halfAddWindowNew}' \
                  --replace-fail '${halfRemoveWindowOld}' '${halfRemoveWindowNew}' \
                  --replace-fail '${buildLayoutSelfHealOld}' '${buildLayoutSelfHealNew}'
              '';
        in
        {
          environment.systemPackages = [
            poloniumPatched
            gapPinner
          ];

          home-manager.sharedModules = [
            {
              programs.plasma = {
                configFile.kwinrc = {
                  Plugins.poloniumEnabled = true;
                  Plugins."icedos-gap-pinEnabled" = true;

                  "Script-polonium" = {
                    LogLevel = 0;
                    DefaultEngine = engineMap.${defaultEngine};
                    Borders = bordersMap.${borders};
                    TileResizeAmount = tileResizeAmount;
                    BTreeInsertionStyle = insertionMap.${btreeInsertionStyle};
                  };

                  "Tiling".padding = gap;
                };

                shortcuts.kwin = {
                  PoloniumActivateAbove = [
                    "Meta+Up"
                    "Meta+K"
                    "Meta+Κ"
                  ];
                  PoloniumActivateBelow = [
                    "Meta+Down"
                    "Meta+J"
                    "Meta+Ξ"
                  ];
                  PoloniumActivateLeft = [
                    "Meta+Left"
                    "Meta+H"
                    "Meta+Η"
                  ];
                  PoloniumActivateRight = [
                    "Meta+Right"
                    "Meta+L"
                    "Meta+Λ"
                  ];

                  PoloniumPlaceAbove = [
                    "Meta+Shift+Up"
                    "Meta+Shift+K"
                    "Meta+Shift+Κ"
                  ];
                  PoloniumPlaceBelow = [
                    "Meta+Shift+Down"
                    "Meta+Shift+J"
                    "Meta+Shift+Ξ"
                  ];
                  PoloniumPlaceLeft = [
                    "Meta+Shift+Left"
                    "Meta+Shift+H"
                    "Meta+Shift+Η"
                  ];
                  PoloniumPlaceRight = [
                    "Meta+Shift+Right"
                    "Meta+Shift+L"
                    "Meta+Shift+Λ"
                  ];

                  PoloniumResizeUp = [
                    "Meta+Ctrl+K"
                    "Meta+Ctrl+Κ"
                  ];
                  PoloniumResizeDown = [
                    "Meta+Ctrl+J"
                    "Meta+Ctrl+Ξ"
                  ];
                  PoloniumResizeLeft = [
                    "Meta+Ctrl+H"
                    "Meta+Ctrl+Η"
                  ];
                  PoloniumResizeRight = [
                    "Meta+Ctrl+L"
                    "Meta+Ctrl+Λ"
                  ];

                  PoloniumToggleActiveTiling = "Meta+T";
                  PoloniumToggleSettingsMenu = "Meta+\\";
                  PoloniumCycleEngine = "Meta+|";

                  "Switch to Desktop 1" = lib.mkDefault "Meta+1";
                  "Switch to Desktop 2" = lib.mkDefault "Meta+2";
                  "Switch to Desktop 3" = lib.mkDefault "Meta+3";
                  "Switch to Desktop 4" = lib.mkDefault "Meta+4";
                  "Switch to Desktop 5" = lib.mkDefault "Meta+5";
                  "Switch to Desktop 6" = lib.mkDefault "Meta+6";
                  "Switch to Desktop 7" = lib.mkDefault "Meta+7";
                  "Switch to Desktop 8" = lib.mkDefault "Meta+8";
                  "Switch to Desktop 9" = lib.mkDefault "Meta+9";
                  "Switch to Desktop 10" = lib.mkDefault "Meta+0";

                  "Window Close" = lib.mkDefault [
                    "Meta+Q"
                    "Meta+;"
                  ];
                  "Window Fullscreen" = [
                    "Meta+F"
                    "Meta+Φ"
                  ];

                  "Window Maximize" = lib.mkDefault "Meta+M";
                  "Window One Screen Up" = "Meta+Alt+Up";
                  "Window One Screen Down" = "Meta+Alt+Down";
                  "Window One Screen to the Left" = "Meta+Alt+Left";
                  "Window One Screen to the Right" = "Meta+Alt+Right";
                  "Edit Tiles" = [ ];
                  "Window Quick Tile Top" = [ ];
                  "Window Quick Tile Bottom" = [ ];
                  "Window Quick Tile Left" = [ ];
                  "Window Quick Tile Right" = [ ];
                  "Switch Window Up" = [ ];
                  "Switch Window Down" = [ ];
                  "Switch Window Left" = [ ];
                  "Switch Window Right" = [ ];
                  "Window to Next Screen" = [ ];
                  "Window to Previous Screen" = [ ];
                };

                # Move lock-screen off Meta+L (PoloniumActivateRight) to
                # Ctrl+Alt+L so a keyboard lock hotkey survives.
                shortcuts.ksmserver."Lock Session" = lib.mkDefault "Ctrl+Alt+L";
              };
            }
          ];
        }
      )
    ];

  meta.name = "polonium";
}
