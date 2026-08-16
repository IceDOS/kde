{ icedosLib, lib, ... }:

{
  options.icedos.desktop.kde.shortcuts =
    let
      inherit (icedosLib) mkAttrsOption;
      inherit (lib) importTOML;

      inherit ((importTOML ./config.toml).icedos.desktop.kde.shortcuts)
        bindings
        hotkeys
        ;
    in
    {
      bindings = mkAttrsOption { default = bindings; };
      hotkeys = mkAttrsOption { default = hotkeys; };
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        { config, ... }:
        let
          inherit (config.icedos.desktop.kde.shortcuts) bindings hotkeys;
        in
        {
          home-manager.sharedModules = [
            {
              programs.plasma.shortcuts = bindings;
              programs.plasma.hotkeys.commands = hotkeys;

              # Walker never sends startup-notification "remove"; suppress
              # KDE busy-cursor feedback for command-hotkey popup launches.
              xdg.desktopEntries = lib.optionalAttrs (hotkeys != { }) {
                "plasma-manager-commands".startupNotify = false;
              };
            }
          ];
        }
      )
    ];

  meta.name = "shortcuts";
}
