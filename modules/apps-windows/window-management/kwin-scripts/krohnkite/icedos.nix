{ icedosLib, lib, ... }:

{
  options.icedos.desktop.kde.krohnkite =
    let
      inherit (icedosLib) mkBoolOption mkIntBetweenOption;
      inherit (lib) importTOML;

      inherit ((importTOML ./config.toml).icedos.desktop.kde.krohnkite)
        gap
        maximizeSoleTile
        ;
    in
    {
      gap = mkIntBetweenOption {
        path = "icedos.desktop.kde.krohnkite.gap";
        source = ./config.toml;
        default = gap;
      } 0 100;

      maximizeSoleTile = mkBoolOption { default = maximizeSoleTile; };
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
          inherit (config.icedos.desktop.kde.krohnkite)
            gap
            maximizeSoleTile
            ;
        in
        {
          environment.systemPackages = [ pkgs.kdePackages.krohnkite ];

          home-manager.sharedModules = [
            {
              programs.plasma = {
                configFile.kwinrc = {
                  Plugins.krohnkiteEnabled = true;

                  "Script-krohnkite" = {
                    inherit maximizeSoleTile;

                    screenGapTop = gap;
                    screenGapBottom = gap;
                    screenGapLeft = gap;
                    screenGapRight = gap;
                    screenGapBetween = gap;
                    spiralLayoutOrder = 1;
                    binaryTreeLayoutOrder = 2;
                    tileLayoutOrder = 3;
                  };
                };

                shortcuts.kwin = {
                  KrohnkiteFocusUp = "Meta+Up";
                  KrohnkiteFocusDown = "Meta+Down";
                  KrohnkiteFocusLeft = "Meta+Left";
                  KrohnkiteFocusRight = "Meta+Right";

                  KrohnkiteShiftUp = "Meta+Shift+Up";
                  KrohnkiteShiftDown = "Meta+Shift+Down";
                  KrohnkiteShiftLeft = "Meta+Shift+Left";
                  KrohnkiteShiftRight = "Meta+Shift+Right";

                  KrohnkiteToggleFloat = "Meta+T";

                  "Window Fullscreen" = [
                    "Meta+F"
                    "Meta+Φ"
                  ];

                  # Monocle / rotate. Second list entry is the Greek-layout keysym
                  # for the same physical key — KWin Wayland matches the active
                  # layout's keysym, so Latin-only bindings die on `gr`.
                  KrohnkiteMonocleLayout = lib.mkDefault "Meta+M";
                  # Free Meta+R from Krohnkite's Rotate so the Walker hotkey wins.
                  # KrohnkiteRotate = lib.mkDefault [ ];

                  # Generic desktop switching + window close.
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

                  # KDE binds Meta+T to its tiling-editor overlay ("Edit Tiles",
                  # the layout-zones UI). Free it so KrohnkiteToggleFloat wins.
                  "Edit Tiles" = [ ];

                  # Meta+Shift+Arrow = Krohnkite move-within-layout (bound above).
                  # Free Meta+Shift+Left/Right from KDE's window-to-screen so the
                  # Krohnkite Shift bindings win uncontested.
                  "Window to Next Screen" = [ ];
                  "Window to Previous Screen" = [ ];

                  # Meta+Alt+Arrow = move window to the adjacent monitor. KWin
                  # built-in — Krohnkite 0.9.9.2 has no screen actions of its own.
                  "Window One Screen Up" = "Meta+Alt+Up";
                  "Window One Screen Down" = "Meta+Alt+Down";
                  "Window One Screen to the Left" = "Meta+Alt+Left";
                  "Window One Screen to the Right" = "Meta+Alt+Right";

                  # Free Meta+Alt+Arrow from its former occupants: KDE quick-tile
                  # (dropped) and KWin's directional window-switch. Full unbind
                  # ([ ]) also kills quick-tile's Meta+Arrow default, which would
                  # otherwise clash with Krohnkite focus.
                  "Window Quick Tile Top" = [ ];
                  "Window Quick Tile Bottom" = [ ];
                  "Window Quick Tile Left" = [ ];
                  "Window Quick Tile Right" = [ ];
                  "Switch Window Up" = [ ];
                  "Switch Window Down" = [ ];
                  "Switch Window Left" = [ ];
                  "Switch Window Right" = [ ];
                };
              };
            }
          ];
        }
      )
    ];

  meta.name = "krohnkite";
}
