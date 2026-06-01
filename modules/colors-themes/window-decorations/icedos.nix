{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      (
        { config, lib, ... }:
        let
          inherit (config.icedos.desktop) windows;
          inherit (lib) concatStrings optional;

          buttonsOnRight = concatStrings (
            optional windows.minimizeButton "I" ++ optional windows.maximizeButton "A" ++ [ "X" ]
          );
        in
        {
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
