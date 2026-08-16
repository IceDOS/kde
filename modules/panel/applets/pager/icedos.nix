{ ... }:

{
  # Not in default layout; kept so adding pager to `widgets` in config.toml
  # restores these settings. Desktop add/remove comes from dynamic_workspaces.
  outputs.nixosModules =
    { ... }:
    [
      {
        icedos.desktop.kde.panel.applets."org.kde.plasma.pager" = {
          pager.general = {
            displayedText = "desktopNumber";
            showOnlyCurrentScreen = true;
            showWindowOutlines = false;
          };
        };
      }
    ];

  meta.name = "panel-pager";
}
