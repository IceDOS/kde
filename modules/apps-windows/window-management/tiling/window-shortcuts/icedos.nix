{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      (
        { lib, ... }:
        {
          icedos.system.tips.list = [
            "Meta+Q closes the window you are using and Meta+F makes it fill the screen."
            "Meta+Alt with an arrow key jumps to another monitor; add Shift to send the window there."
            "The screen locks with Ctrl+Alt+L, because Meta+L moves focus."
          ];

          home-manager.sharedModules = [
            {
              programs.plasma = {
                shortcuts.kwin = {
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
                  "Window Maximize" = lib.mkDefault [
                    "Meta+M"
                    "Meta+Μ"
                  ];

                  "Switch to Screen Above" = "Meta+Alt+Up";
                  "Switch to Screen Below" = "Meta+Alt+Down";
                  "Switch to Screen to the Left" = "Meta+Alt+Left";
                  "Switch to Screen to the Right" = "Meta+Alt+Right";
                  "Window One Screen Up" = "Meta+Shift+Alt+Up";
                  "Window One Screen Down" = "Meta+Shift+Alt+Down";
                  "Window One Screen to the Left" = "Meta+Shift+Alt+Left";
                  "Window One Screen to the Right" = "Meta+Shift+Alt+Right";

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
                  # Zoom default Meta+0 clashes with Switch to Desktop 10.
                  view_actual_size = [ ];
                };

                # Plasma defaults grab Meta+1..9 and Meta+Q before KWin sees them.
                shortcuts.plasmashell = {
                  "manage activities" = [ ];
                }
                // lib.genAttrs (map (n: "activate task manager entry ${toString n}") (lib.range 1 10)) (_: [ ]);

                shortcuts.ksmserver."Lock Session" = lib.mkDefault "Ctrl+Alt+L";
              };
            }
          ];
        }
      )
    ];

  meta.name = "window-shortcuts";
}
