{ icedosLib, lib, ... }:

{
  options.icedos.desktop.kde.session =
    let
      inherit (icedosLib) mkEnumOption;
      inherit (lib) importTOML;
      inherit ((importTOML ./config.toml).icedos.desktop.kde.session) restorePrevious;
    in
    {
      restorePrevious =
        mkEnumOption
          {
            path = "icedos.desktop.kde.session.restorePrevious";
            source = toString ./config.toml;
            default = restorePrevious;
          }
          [
            false
            true
            "saved"
          ];
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        { config, ... }:
        let
          inherit (config.icedos.desktop.kde.session) restorePrevious;
          inherit (lib) optionals;
        in
        {
          icedos.system.tips.list =
            optionals (restorePrevious == true) [
              "The apps you leave open come back the next time you log in."
            ]
            ++ optionals (restorePrevious == "saved") [
              "Plasma reopens the session you saved by hand, so save one once you have things arranged."
            ]
            ++ optionals (restorePrevious == false) [
              "Have Plasma reopen your apps after login with restorePrevious under [icedos.desktop.kde.session]."
            ];

          home-manager.sharedModules = [
            {
              programs.plasma.session.sessionRestore.restoreOpenApplicationsOnLogin =
                if builtins.isBool restorePrevious then
                  if restorePrevious then "onLastLogout" else "startWithEmptySession"
                else
                  "whenSessionWasManuallySaved";
            }
          ];
        }
      )
    ];

  meta.name = "desktop-session";
}
