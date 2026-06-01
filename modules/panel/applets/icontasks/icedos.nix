{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      {
        icedos.desktop.kde.panel.applets."org.kde.plasma.icontasks" = {
          iconTasks.launchers = [ ];
        };
      }
    ];

  meta.name = "panel-icontasks";
}
