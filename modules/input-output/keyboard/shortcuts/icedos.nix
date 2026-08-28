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
          # Hotkey display name defaults to the attribute key.
          inherit (config.icedos.desktop.kde.shortcuts) bindings hotkeys;
        in
        {
          home-manager.sharedModules = [
            {
              programs.plasma.shortcuts = bindings;
              programs.plasma.hotkeys.commands = hotkeys;
            }
          ];
        }
      )
    ];

  meta.name = "shortcuts";
}
