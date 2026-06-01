{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      {
        icedos.desktop.kde.panel.applets."org.kde.plasma.panelspacer" = {
          panelSpacer.expanding = true;
        };
      }
    ];

  meta.name = "panel-spacer";
}
