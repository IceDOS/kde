{ icedosLib, lib, ... }:

{
  options.icedos.desktop.kde.dynamic-workspaces =
    # NOTE: polonium/icedos.nix keys its evUpdateWindow patch off this option
    # path existing (config.icedos.desktop.kde.dynamic-workspaces or null !=
    # null). If this root path is ever renamed, update that check too — it
    # degrades to stock polonium silently otherwise.
    let
      inherit (icedosLib) mkBoolOption mkEnumOption mkIntBetweenOption;
      inherit (lib) importTOML;

      inherit ((importTOML ./config.toml).icedos.desktop.kde.dynamic-workspaces)
        number
        orientation
        perScreen
        ;
    in
    {
      orientation =
        mkEnumOption
          {
            path = "icedos.desktop.kde.dynamic-workspaces.orientation";
            source = ./config.toml;
            default = orientation;
          }
          [
            "Horizontal"
            "Vertical"
          ];

      number = mkIntBetweenOption {
        path = "icedos.desktop.kde.dynamic-workspaces.number";
        source = ./config.toml;
        default = number;
      } 1 20;

      perScreen = mkBoolOption { default = perScreen; };
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
          inherit (config.icedos.desktop.kde.dynamic-workspaces)
            number
            orientation
            perScreen
            ;

          script =
            pkgs.runCommandLocal "kwin-dynamic-workspaces-omni"
              {
                meta = {
                  description = "Omnidirectional dynamic workspaces KWin script";
                  # main.js is adapted from maurges/dynamic_workspaces (BSD-3-Clause).
                  license = lib.licenses.bsd3;
                };
              }
              ''
                dir="$out/share/kwin/scripts/dynamic-workspaces-omni"
                mkdir -p "$dir/contents/code"
                cp ${./metadata.json} "$dir/metadata.json"
                cp ${
                  pkgs.replaceVars ./main.js {
                    PER_SCREEN = if perScreen then "true" else "false";
                  }
                } "$dir/contents/code/main.js"
              '';
        in
        {
          environment.systemPackages = [ script ];

          home-manager.sharedModules = [
            {
              programs.plasma = {
                kwin.virtualDesktops = {
                  inherit number;
                  rows = if orientation == "Horizontal" then 1 else number;
                };

                configFile.kwinrc = {
                  Windows.PerOutputVirtualDesktops = perScreen;
                  Plugins."dynamic-workspaces-omniEnabled" = true;
                };

                shortcuts.kwin = {
                  "Switch One Desktop to the Left" = "Meta+Ctrl+Left";
                  "Switch One Desktop to the Right" = "Meta+Ctrl+Right";

                  "Window One Desktop to the Left" = "Meta+Ctrl+Shift+Left";
                  "Window One Desktop to the Right" = "Meta+Ctrl+Shift+Right";
                };
              };
            }
          ];
        }
      )
    ];

  meta.name = "dynamic-workspaces";
}
