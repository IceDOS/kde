{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      (
        { config, lib, ... }:
        let
          inherit (config.icedos.desktop) windows;
          inherit (lib) concatStrings optional optionals;

          buttonsOnRight = concatStrings (
            optional windows.minimizeButton "I" ++ optional windows.maximizeButton "A" ++ [ "X" ]
          );
        in
        {
          icedos.system.tips.list = optionals (!windows.minimizeButton || !windows.maximizeButton) [
            "Your titlebars show only the buttons you kept; double-click a titlebar to maximize."
          ];

          home-manager.sharedModules = [
            {
              programs.plasma.configFile.kwinrc."org.kde.kdecoration2".ButtonsOnRight = buttonsOnRight;
            }
          ];
        }
      )
    ];

  meta.name = "window-decorations";
}
