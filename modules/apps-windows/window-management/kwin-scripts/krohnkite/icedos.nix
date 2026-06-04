{ icedosLib, lib, ... }:

{
  options.icedos.desktop.kde.krohnkite =
    let
      inherit (icedosLib) mkBoolOption mkIntBetweenOption;
      inherit (lib) readFile;

      inherit ((fromTOML (readFile ./config.toml)).icedos.desktop.kde.krohnkite)
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

                  KrohnkiteToggleFloat = "Meta+G";

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

                  "Window Close" = lib.mkDefault "Meta+Q";

                  # Free the arrow keys from KWin's built-in quick-tile so the
                  # krohnkite focus bindings above win.
                  # "Window Quick Tile Top" = [ ];
                  # "Window Quick Tile Bottom" = [ ];
                  # "Window Quick Tile Left" = [ ];
                  # "Window Quick Tile Right" = [ ];
                };
              };
            }
          ];
        }
      )
    ];

  meta.name = "krohnkite";
}
