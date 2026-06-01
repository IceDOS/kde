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

                  # Free the arrow keys from KWin's built-in quick-tile so the
                  # krohnkite focus bindings above win.
                  "Window Quick Tile Top" = [ ];
                  "Window Quick Tile Bottom" = [ ];
                  "Window Quick Tile Left" = [ ];
                  "Window Quick Tile Right" = [ ];
                };
              };
            }
          ];
        }
      )
    ];

  meta.name = "krohnkite";
}
