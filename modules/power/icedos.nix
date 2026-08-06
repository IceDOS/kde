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
                # Screen locking. kscreenlocker timeout is in MINUTES,
                # idle.lock.seconds is in seconds — convert.
                # (Keep spaces around `/`; `lock.seconds/60` parses as a path.)
                # Ceil to whole minutes and floor at 1 so a sub-60s value locks
                # after a minute instead of silently truncating to 0.
                programs.plasma.kscreenlocker = {
                  autoLock = lock.enable;
                  timeout = lib.max 1 ((lock.seconds + 59) / 60);
                };

                programs.plasma.powerdevil.AC = {
                  # Turn off monitors after idle. plasma-manager's type floor is
                  # 30s (int 30..600000 or "never") — clamp so a lower value
                  # builds instead of failing the type check.
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
