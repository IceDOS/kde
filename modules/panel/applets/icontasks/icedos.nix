{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      (
        { config, lib, ... }:
        let
          inherit (config.icedos.desktop.kde.panel) favorites;
          inherit (lib) mkIf removeSuffix;
        in
        {
          # Only manage the pinned launchers when favorites are set. An empty
          # list leaves the key unmanaged so hand-placed pins are preserved.
          icedos.desktop.kde.panel.applets = mkIf (favorites != [ ]) {
            "org.kde.plasma.icontasks".iconTasks.launchers = map (
              favorite: "applications:${removeSuffix ".desktop" favorite}.desktop"
            ) favorites;
          };
        }
      )
    ];

  meta.name = "panel-icontasks";
}
