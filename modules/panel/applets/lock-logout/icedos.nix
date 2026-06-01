{ ... }:

{
  # Power/session applet. Not in the shipped default layout — kept as a module
  # so adding "org.kde.plasma.lock_logout" to `widgets` in config.toml restores
  # it with these settings (lock entry hidden, full session-action order).
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
