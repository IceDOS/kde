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
        { config, ... }:
        let
          inherit (config.icedos.desktop.windows) focus;
          inherit (config.icedos.desktop.kde.windowBehavior.focus) separateScreenFocus;
        in
        {
          home-manager.sharedModules = [
            {
              programs.plasma.configFile.kwinrc.Windows = {
                FocusPolicy = if focus.followMouse then "FocusFollowsMouse" else "ClickToFocus";
                DelayFocusInterval = focus.delay;
                SeparateScreenFocus = separateScreenFocus;
              };
            }
          ];
        }
      )
    ];

  meta.name = "focus";
}
