{ ... }:

{
  # Not in default layout; kept so adding pager to `widgets` in config.toml
  # restores these settings. Desktop add/remove comes from dynamic_workspaces.
  outputs.nixosModules =
    { ... }:
    [
      (
        { config, lib, ... }:
        let
          inherit (config.icedos.desktop.kde.panel) widgets;
          inherit (lib) elem optionals;

          onPanel = elem "org.kde.plasma.pager" widgets;
        in
        {
          icedos.system.tips.list =
            optionals onPanel [
              "The pager in your panel numbers your desktops; click one to jump there."
            ]
            ++ optionals (!onPanel) [
              "Add org.kde.plasma.pager to widgets under [icedos.desktop.kde.panel] to switch desktops from the panel."
            ];

          icedos.desktop.kde.panel.applets."org.kde.plasma.pager" = {
            pager.general = {
              displayedText = "desktopNumber";
              showOnlyCurrentScreen = true;
              showWindowOutlines = false;
            };
          };
        }
      )
    ];

  meta.name = "panel-pager";
}
