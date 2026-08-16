{ ... }:

{
  # Not in default layout; kept so adding lock_logout to `widgets` in
  # config.toml restores these settings.
  outputs.nixosModules =
    { ... }:
    [
      {
        icedos.desktop.kde.panel.applets."org.kde.plasma.lock_logout" = {
          name = "org.kde.plasma.lock_logout";
          config.General = {
            actionsOrder = "lockScreen,switchUser,requestShutDown,requestReboot,requestLogout,requestLogoutScreen,suspendToRam,suspendToDisk";
            show_lockScreen = false;
          };
        };
      }
    ];

  meta.name = "panel-lock-logout";
}
