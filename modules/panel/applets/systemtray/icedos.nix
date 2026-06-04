{ icedosLib, lib, ... }:

{
  options.icedos.desktop.kde.panel.systemTray =
    let
      inherit (lib) readFile;

      inherit ((fromTOML (readFile ./config.toml)).icedos.desktop.kde.panel.systemTray)
        disabledApplets
        knownApplets
        ;
    in
    {
      # Full set of tray applets the framework manages (plasma's knownItems).
      knownApplets = icedosLib.mkStrListOption { default = knownApplets; };

      # Applet plugin IDs (e.g. "org.kde.plasma.clipboard") removed from the
      # enabled set (extraItems) while kept in knownItems — plasma's
      # "Never show (disabled)" entry state.
      disabledApplets = icedosLib.mkStrListOption { default = disabledApplets; };
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        { config, lib, ... }:
        let
          cfg = config.icedos.desktop.kde.panel.systemTray;
        in
        {
          icedos.desktop.kde.panel.applets."org.kde.plasma.systemtray" = {
            name = "org.kde.plasma.systemtray";
            config.General = {
              scaleIconsToFit = true;
              knownItems = cfg.knownApplets;
              # extraItems must be written explicitly; an absent key makes plasma
              # treat the tray as fresh and repopulate every default plasmoid,
              # ignoring the disable.
              extraItems = lib.subtractLists cfg.disabledApplets cfg.knownApplets;
            };
          };
        }
      )
    ];

  meta.name = "panel-systemtray";
}
