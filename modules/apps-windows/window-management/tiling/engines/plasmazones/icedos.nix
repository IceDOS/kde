{ icedosLib, lib, ... }:

{
  inputs.plasmazones = {
    url = "github:fuddlesworth/PlasmaZones";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  options.icedos.desktop.kde.plasmazones =
    let
      inherit (icedosLib) mkIntBetweenOption mkNonEmptyStrOption;
      inherit ((lib.importTOML ./config.toml).icedos.desktop.kde.plasmazones) algorithm gap;
    in
    {
      algorithm = mkNonEmptyStrOption { default = algorithm; };

      gap = mkIntBetweenOption {
        path = "icedos.desktop.kde.plasmazones.gap";
        source = ./config.toml;
        default = gap;
      } 0 100;
    };

  outputs.nixosModules =
    { inputs, ... }:
    [
      inputs.plasmazones.nixosModules.default
      (
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          inherit (config.icedos.desktop.kde.plasmazones) algorithm gap;

          # kglobalshortcutsrc decides the active keys; these keep config.json in step with it.
          shortcuts = pkgs.writeText "plasmazones-shortcuts.json" (
            builtins.toJSON {
              Global = {
                FocusZoneLeft = "Meta+Left";
                FocusZoneRight = "Meta+Right";
                FocusZoneUp = "Meta+Up";
                FocusZoneDown = "Meta+Down";
                MoveWindowLeft = "Meta+Shift+Left";
                MoveWindowRight = "Meta+Shift+Right";
                MoveWindowUp = "Meta+Shift+Up";
                MoveWindowDown = "Meta+Shift+Down";
                ToggleWindowFloat = "Meta+T";
                ToggleLayoutLock = "";
              };
              Tiling = {
                IncMasterRatio = "Meta+Ctrl+L";
                DecMasterRatio = "Meta+Ctrl+H";
                Toggle = "";
              };
            }
          );

          merge = pkgs.writeShellApplication {
            name = "icedos-plasmazones-merge";
            runtimeInputs = [ pkgs.jq ];
            excludeShellChecks = [ "SC2016" ];
            text = builtins.readFile ./merge-settings.sh;
          };
        in
        {
          programs.plasmazones = {
            enable = true;
            autostart = true;
          };

          # The "-" prefix lets the daemon start even if the merge fails.
          systemd.user.services.plasmazones.serviceConfig.ExecStartPre =
            "-${lib.getExe merge} ${lib.escapeShellArg algorithm} ${toString gap} ${shortcuts}";

          icedos.system.tips.list = [
            "Every window tiles by itself. Meta+T floats the one you are using, or tiles it again."
            "Meta with an arrow key or HJKL jumps between tiled windows; add Shift to move the window itself."
            "Drag the edge between two windows to resize them. Meta+Ctrl+H and Meta+Ctrl+L change the split at the next retile."
            "Drag a window onto another one to put it in that slot."
          ];

          home-manager.sharedModules = [
            {
              programs.plasma.shortcuts.plasmazonesd = {
                focus_zone_left = [
                  "Meta+Left"
                  "Meta+H"
                  "Meta+Η"
                ];
                focus_zone_right = [
                  "Meta+Right"
                  "Meta+L"
                  "Meta+Λ"
                ];
                focus_zone_up = [
                  "Meta+Up"
                  "Meta+K"
                  "Meta+Κ"
                ];
                focus_zone_down = [
                  "Meta+Down"
                  "Meta+J"
                  "Meta+Ξ"
                ];
                move_window_left = [
                  "Meta+Shift+Left"
                  "Meta+Shift+H"
                  "Meta+Shift+Η"
                ];
                move_window_right = [
                  "Meta+Shift+Right"
                  "Meta+Shift+L"
                  "Meta+Shift+Λ"
                ];
                move_window_up = [
                  "Meta+Shift+Up"
                  "Meta+Shift+K"
                  "Meta+Shift+Κ"
                ];
                move_window_down = [
                  "Meta+Shift+Down"
                  "Meta+Shift+J"
                  "Meta+Shift+Ξ"
                ];
                toggle_window_float = [
                  "Meta+T"
                  "Meta+Τ"
                ];
                increase_master_ratio = [
                  "Meta+Ctrl+L"
                  "Meta+Ctrl+Λ"
                ];
                decrease_master_ratio = [
                  "Meta+Ctrl+H"
                  "Meta+Ctrl+Η"
                ];
                # Would leave autotile or block tiling, and "" in config.json does not clear them.
                toggle_autotile = [ ];
                toggle_layout_lock = [ ];
              };
            }
          ];
        }
      )
    ];

  meta = {
    name = "plasmazones";

    dependencies = [
      {
        modules = [ "window-shortcuts" ];
      }
    ];
  };
}
