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
        let
          inherit (config.icedos.desktop.kde.splash-screen) theme;
        in
        {
          icedos.system.tips.list =
            lib.optionals (theme == "None") [
              "Show a loading screen at login with theme under [icedos.desktop.kde.splash-screen]."
            ]
            ++ lib.optionals (theme != "None") [
              "Your login loading screen comes from theme under [icedos.desktop.kde.splash-screen]."
            ];

          home-manager.sharedModules = [
            {
              programs.plasma.workspace.splashScreen.theme = theme;
            }
          ];
        }
      )
    ];

  meta.name = "splash-screen";
}
