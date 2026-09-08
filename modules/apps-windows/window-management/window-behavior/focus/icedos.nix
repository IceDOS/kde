{ icedosLib, lib, ... }:

{
  options.icedos.desktop.kde.window-behavior.focus =
    let
      inherit (icedosLib) mkBoolOption;
      inherit (lib) importTOML;

      inherit ((importTOML ./config.toml).icedos.desktop.kde.window-behavior.focus)
        separateScreenFocus
        ;
    in
    {
      separateScreenFocus = mkBoolOption { default = separateScreenFocus; };
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        { config, lib, ... }:
        let
          inherit (config.icedos.desktop) kde windows;
          inherit (kde.window-behavior.focus) separateScreenFocus;
          inherit (lib) optionalAttrs optionals;
          inherit (windows) focus;
          inherit (focus) delay followsMouse;
        in
        {
          icedos.system.tips.list =
            optionals followsMouse [
              "A window takes focus once the mouse rests on it; the wait is delay under [icedos.desktop.windows.focus]."
            ]
            ++ optionals (!followsMouse) [
              "Set followsMouse under [icedos.desktop.windows.focus] to switch windows by pointing instead of clicking."
            ]
            ++ optionals separateScreenFocus [
              "Each monitor remembers the window you last used on it."
            ];

          home-manager.sharedModules = [
            {
              programs.plasma.configFile.kwinrc.Windows = {
                DelayFocusInterval = delay;
                FocusPolicy = if followsMouse then "FocusFollowsMouse" else "ClickToFocus";
                SeparateScreenFocus = separateScreenFocus;
              }
              // optionalAttrs followsMouse { NextFocusPrefersMouse = true; };
            }
          ];
        }
      )
    ];

  meta.name = "focus";
}
