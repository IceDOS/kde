{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      (
        { config, lib, ... }:
        let
          inherit (config.icedos.desktop.kde.panel) widgets;
          inherit (lib) elem optionals;

          onPanel = elem "org.kde.plasma.panelspacer" widgets;
        in
        {
          icedos.system.tips.list =
            optionals onPanel [
              "The spacer in your panel is what pushes the clock and tray to the far end."
            ]
            ++ optionals (!onPanel) [
              "Add org.kde.plasma.panelspacer to widgets under [icedos.desktop.kde.panel] to push later items to the far end."
            ];

          icedos.desktop.kde.panel.applets."org.kde.plasma.panelspacer" = {
            panelSpacer.expanding = true;
          };
        }
      )
    ];

  meta.name = "panel-spacer";
}
