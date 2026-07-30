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
        in
        {
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
