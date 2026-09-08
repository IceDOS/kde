{ ... }:

{
  # Not in default layout; kept so adding lock_logout to `widgets` in
  # config.toml restores these settings.
  outputs.nixosModules =
    { ... }:
    [
      (
        { config, lib, ... }:
        let
          inherit (config.icedos.desktop.kde.panel) widgets;
          inherit (lib) elem optionals;

          onPanel = elem "org.kde.plasma.lock_logout" widgets;
        in
        {
          icedos.system.tips.list =
            optionals onPanel [
              "The lock and logout widget in your panel holds shutdown, restart and sleep."
            ]
            ++ optionals (!onPanel) [
              "Add org.kde.plasma.lock_logout to widgets under [icedos.desktop.kde.panel] for shutdown and sleep buttons."
            ];

          icedos.desktop.kde.panel.applets."org.kde.plasma.lock_logout" = {
            name = "org.kde.plasma.lock_logout";
            config.General = {
              actionsOrder = "lockScreen,switchUser,requestShutDown,requestReboot,requestLogout,requestLogoutScreen,suspendToRam,suspendToDisk";
              show_lockScreen = false;
            };
          };
        }
      )
    ];

  meta.name = "panel-lock-logout";
}
