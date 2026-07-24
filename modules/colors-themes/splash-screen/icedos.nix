{ icedosLib, lib, ... }:

{
  options.icedos.desktop.kde.splash-screen =
    let
      inherit (icedosLib) mkStrOption;
      inherit (lib) importTOML;

      inherit ((importTOML ./config.toml).icedos.desktop.kde.splash-screen)
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
              programs.plasma.workspace.splashScreen.theme = config.icedos.desktop.kde.splash-screen.theme;
            }
          ];
        }
      )
    ];

  meta.name = "splash-screen";
}
