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

          # The race this patch fixes is only realistic when a desktop can be
          # removed out from under Polonium's queued desktopsChanged events,
          # which in practice only dynamic-workspaces does (it auto-removes
          # empty desktops). Without dynamic-workspaces loaded, ship stock
          # polonium untouched. The option path only exists when the
          # dynamic-workspaces module is part of this config, so its presence
          # is the enable signal.
          useDynamicWorkspaces = (config.icedos.desktop.kde.dynamic-workspaces or null) != null;

          # Polonium's evUpdateWindow, verbatim from the packaged main.mjs
          # (polonium 1.2.1). When the desktop a window just left is removed
          # before Polonium processes its queued desktopsChanged event (our
          # dynamic-workspaces script defers removals, but any desktop churn
          # can race), getDriver() can't resolve the old display because the
          # desktop object is gone — either its QObject is destroyed
          # (desktop.id is undefined) or it has been dropped from the live
          # workspace.desktops list — and Polonium silently untiles the moved
          # window. Only in that case do we assume the window was tiled —
          # gated on the handler's own wantsTiled so genuinely floating
          # windows are never force-tiled — and it stays tiled on the new
          # desktop. Applied only when dynamic-workspaces is enabled
          # (useDynamicWorkspaces); drop this patch if/once fixed upstream;
          # --replace-fail breaks the build loudly if a polonium bump
          # reshapes the block.
          poloniumPatchOld = "      const driver = this.getDriver(oldDisplay);\n      if (driver === void 0) {\n        continue;\n      }\n      if (driver.isWindowTiled(window)) {\n        tiled = true;\n      }";
          poloniumPatchNew = "      const driver = this.getDriver(oldDisplay);\n      if (driver === void 0) {\n        if ((oldDisplay.desktop?.id === void 0 || !this.workspace.desktops.includes(oldDisplay.desktop)) && this.windowHandlers.get(window)?.wantsTiled) {\n          tiled = true;\n        }\n        continue;\n      }\n      if (driver.isWindowTiled(window)) {\n        tiled = true;\n      }";

          poloniumPatched =
            pkgs.runCommandLocal "polonium-icedos"
              {
                meta = {
                  description = "Polonium with a fix for windows floating after cross-desktop moves";
                  homepage = "https://polonium.vaughanm.xyz/";
                  license = lib.licenses.mit;
                };
              }
              ''
                mkdir -p "$out"
                cp -r ${pkgs.polonium}/. "$out/"
                chmod -R u+w "$out"
                substituteInPlace "$out/share/kwin/scripts/polonium/contents/code/main.mjs" \
                  --replace-fail '${poloniumPatchOld}' '${poloniumPatchNew}'
              '';
        in
        {
          environment.systemPackages = [
            (if useDynamicWorkspaces then poloniumPatched else pkgs.polonium)
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
