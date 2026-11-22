{ icedosLib, lib }:

let
  inherit (icedosLib) mkBoolOption mkStrOption;
  inherit ((lib.importTOML ./config.toml).icedos.desktop.kde.bigscreen)
    appName
    headless
    replacePlasma
    ;
in
{
  appName = mkStrOption { default = appName; };

  headless = mkBoolOption { default = headless; };

  replacePlasma = mkBoolOption { default = replacePlasma; };
}
