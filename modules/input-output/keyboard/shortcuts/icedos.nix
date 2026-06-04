{ icedosLib, lib, ... }:

{
  options.icedos.desktop.kde.shortcuts =
    let
      inherit (icedosLib) mkAttrsOption;
      inherit (lib) readFile;

      inherit ((fromTOML (readFile ./config.toml)).icedos.desktop.kde.shortcuts)
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

              # Walker is a layer-shell overlay (as_window = false): it never sends
              # the startup-notification "remove" message, so KDE's busy-cursor
              # launch feedback bounces for the full timeout. Mark the generated
              # command-hotkey launcher as not supporting startup notification,
              # suppressing the feedback for these popup launches only (normal apps
              # keep their launch feedback).
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
