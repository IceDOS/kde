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
              { config, ... }:
              let
                inherit (desktop.users.${config.home.username}.idle)
                  disableMonitors
                  lock
                  suspend
                  ;
              in
              {
                # Screen locking. kscreenlocker timeout is in MINUTES,
                # idle.lock.seconds is in seconds — convert.
                # (Keep spaces around `/`; `lock.seconds/60` parses as a path.)
                programs.plasma.kscreenlocker = {
                  autoLock = lock.enable;
                  timeout = lock.seconds / 60;
                };

                programs.plasma.powerdevil.AC = {
                  # Turn off monitors after idle
                  turnOffDisplay.idleTimeout = if disableMonitors.enable then disableMonitors.seconds else "never";

                  # Auto suspend after idle
                  autoSuspend = {
                    action = if suspend.enable then "sleep" else "nothing";
                    idleTimeout = suspend.seconds;
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
