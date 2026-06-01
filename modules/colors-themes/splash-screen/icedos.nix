{ icedosLib, lib, ... }:

{
  options.icedos.desktop.kde.splashScreen =
    let
      inherit (icedosLib) mkStrOption;
      inherit (lib) readFile;

      inherit ((fromTOML (readFile ./config.toml)).icedos.desktop.kde.splashScreen)
        theme
        ;
    in
    {
      theme = mkStrOption { default = theme; };
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        { config, ... }:
        {
          home-manager.sharedModules = [
            {
              programs.plasma.workspace.splashScreen.theme = config.icedos.desktop.kde.splashScreen.theme;
            }
          ];
        }
      )
    ];

  meta.name = "splash-screen";
}
