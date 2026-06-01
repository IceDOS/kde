{ icedosLib, lib, ... }:

{
  options.icedos.desktop.kde.windowBehavior.focus =
    let
      inherit (icedosLib)
        mkBoolOption
        mkEnumOption
        mkIntBetweenOption
        ;

      inherit (lib) readFile;

      inherit ((fromTOML (readFile ./config.toml)).icedos.desktop.kde.windowBehavior.focus)
        delay
        policy
        separateScreenFocus
        ;
    in
    {
      policy =
        mkEnumOption
          {
            path = "icedos.desktop.kde.windowBehavior.focus.policy";
            source = ./config.toml;
            default = policy;
          }
          [
            "click-to-focus"
            "focus-follows-mouse"
            "focus-under-mouse"
            "focus-strictly-under-mouse"
          ];

      delay = mkIntBetweenOption {
        path = "icedos.desktop.kde.windowBehavior.focus.delay";
        source = ./config.toml;
        default = delay;
      } 0 3000;

      separateScreenFocus = mkBoolOption { default = separateScreenFocus; };
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        { config, ... }:
        let
          inherit (config.icedos.desktop.kde.windowBehavior.focus)
            delay
            policy
            separateScreenFocus
            ;

          focusPolicies = {
            "click-to-focus" = "ClickToFocus";
            "focus-follows-mouse" = "FocusFollowsMouse";
            "focus-under-mouse" = "FocusUnderMouse";
            "focus-strictly-under-mouse" = "FocusStrictlyUnderMouse";
          };
        in
        {
          home-manager.sharedModules = [
            {
              programs.plasma.configFile.kwinrc.Windows = {
                FocusPolicy = focusPolicies.${policy};
                DelayFocusInterval = delay;
                SeparateScreenFocus = separateScreenFocus;
              };
            }
          ];
        }
      )
    ];

  meta.name = "focus";
}
