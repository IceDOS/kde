{ ... }:

{
  # Numbers-only pager. Not in the shipped default layout (kickoff takes the
  # leading slot) — kept as a module so adding "org.kde.plasma.pager" to
  # `widgets` in config.toml restores it with these settings. The dynamic
  # add/remove of desktops still comes from the dynamic_workspaces script.
  outputs.nixosModules =
    { ... }:
    [
      {
        icedos.desktop.kde.panel.applets."org.kde.plasma.pager" = {
          pager.general = {
            displayedText = "desktopNumber";
            showWindowOutlines = false;
          };
        };
      }
    ];

  meta.name = "panel-pager";
}
