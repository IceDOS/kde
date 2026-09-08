{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      (
        { config, ... }:
        let
          inherit (config.icedos) desktop;
        in
        {
          icedos.system.tips.list = [
            "Set how long before the screen locks itself under [icedos.desktop.users.<name>.idle.lock]."
            "Set how long before the machine sleeps on its own under [icedos.desktop.users.<name>.idle.suspend]."
            "Set how long before the monitors turn off under [icedos.desktop.users.<name>.idle.disable-monitors]."
          ];

          home-manager.sharedModules = [
            (
              { config, lib, ... }:
              let
                inherit (desktop.users.${config.home.username}.idle)
                  lock
                  suspend
                  ;

                disableMonitors = desktop.users.${config.home.username}.idle.disable-monitors;

                inherit (lib) mkIf;
              in
              {
                # Convert idle.lock.seconds (seconds) to kscreenlocker minutes.
                # Ceil and floor at 1 so sub-60s values lock after one minute.
                programs.plasma.kscreenlocker = {
                  autoLock = lock.enable;
                  timeout = lib.max 1 ((lock.seconds + 59) / 60);
                };

                programs.plasma.powerdevil.AC = {
                  # Turn off monitors after idle. Clamp to 30s floor
                  # (plasma-manager type range) so lower values build.
                  turnOffDisplay.idleTimeout =
                    if disableMonitors.enable then lib.max 30 disableMonitors.seconds else "never";

                  # Auto suspend after idle. Same floor logic: plasma-manager
                  # requires int 60..600000 seconds.
                  autoSuspend = {
                    action = if suspend.enable then "sleep" else "nothing";
                    idleTimeout = mkIf suspend.enable (lib.max 60 suspend.seconds);
                  };
                };
              }
            )
          ];
        }
      )
    ];

  meta.name = "power";
}
