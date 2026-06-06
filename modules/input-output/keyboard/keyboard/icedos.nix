{ icedosLib, lib, ... }:

{
  options.icedos.desktop.kde.keyboard =
    let
      inherit (icedosLib) mkEnumOption;
      inherit (lib) readFile;

      inherit ((fromTOML (readFile ./config.toml)).icedos.desktop.kde.keyboard)
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
          inherit (lib) mkIf;
        in
        {
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
