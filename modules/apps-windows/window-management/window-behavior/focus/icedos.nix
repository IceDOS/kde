{ icedosLib, lib, ... }:

{
  options.icedos.desktop.kde.windowBehavior.focus =
    let
      inherit (icedosLib) mkBoolOption;
      inherit (lib) readFile;

      inherit ((fromTOML (readFile ./config.toml)).icedos.desktop.kde.windowBehavior.focus)
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
          inherit (kde.windowBehavior.focus) separateScreenFocus;
          inherit (lib) optionalAttrs;
          inherit (windows) focus;
          inherit (focus) delay followsMouse;
        in
        {
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
