{ icedosLib, lib }:

let
  inherit (icedosLib) mkBoolOption mkEnumOption mkStrOption;
  inherit ((lib.importTOML ./config.toml).icedos.desktop.kde.virtual-session)
    appName
    home
    publishDesktop
    ;
in
{
  appName = mkStrOption { default = appName; };

  home =
    mkEnumOption
      {
        path = "icedos.desktop.kde.virtual-session.home";
        source = ./config.toml;
        default = home;
      }
      [
        "isolated"
        "shared"
      ];

  publishDesktop = mkBoolOption { default = publishDesktop; };
}
