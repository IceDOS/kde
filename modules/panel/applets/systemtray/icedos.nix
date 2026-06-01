{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      {
        icedos.desktop.kde.panel.applets."org.kde.plasma.systemtray" = {
          systemTray.icons.scaleToFit = true;
        };
      }
    ];

  meta.name = "panel-systemtray";
}
