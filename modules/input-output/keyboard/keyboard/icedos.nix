{ icedosLib, lib, ... }:

{
  options.icedos.desktop.kde.keyboard =
    let
      inherit (icedosLib) mkEnumOption;
      inherit (lib) importTOML;

      inherit ((importTOML ./config.toml).icedos.desktop.kde.keyboard)
        switchingPolicy
        ;
    in
    {
      switchingPolicy =
        mkEnumOption
          {
            path = "icedos.desktop.kde.keyboard.switchingPolicy";
            source = ./config.toml;
            default = switchingPolicy;
          }
          [
            "global"
            "desktop"
            "winClass"
            "window"
          ];
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        { config, ... }:
        let
          inherit (config.icedos.desktop) keyboardLayouts;
          inherit (config.icedos.desktop.kde.keyboard) switchingPolicy;
          inherit (lib) length mkIf optionals;
        in
        {
          icedos.system.tips.list = optionals (length keyboardLayouts > 1) [
            "Meta+Space switches to your next keyboard layout."
            "Pick what a layout switch covers with switchingPolicy under [icedos.desktop.kde.keyboard]."
          ];

          home-manager.sharedModules = [
            (mkIf (keyboardLayouts != [ ]) {
              programs.plasma.input.keyboard = {
                layouts = map (layout: { inherit layout; }) keyboardLayouts;
                options = [ "grp:win_space_toggle" ];
                inherit switchingPolicy;
              };
            })
          ];
        }
      )
    ];

  meta.name = "keyboard";
}
