{
  config ? { },
  icedosLib,
  lib,
  ...
}:

let
  isHeadless = config.desktop.kde.bigscreen.headless or false;
in
{
  options.icedos.desktop.kde.bigscreen = import ./options.nix {
    inherit icedosLib lib;
  };

  outputs.nixosModules =
    { ... }:
    [
      (
        {
          config,
          lib,
          pkgs,
          ...
        }:

        let
          cfg = config.icedos.desktop.kde.bigscreen;
          replacePlasma = cfg.replacePlasma;
        in
        lib.mkMerge (
          [
            {
              environment.systemPackages = [
                pkgs.kdePackages.plasma-bigscreen
                pkgs.kdePackages.plasma-nm
                pkgs.kdePackages.kdeconnect-kde
              ];
              services.udev.packages = [ pkgs.kdePackages.plasma-bigscreen ];

              # mkForce drops normal plasma and any other DE sessions on this host.
              services.displayManager.sessionPackages =
                if replacePlasma then
                  lib.mkForce [ pkgs.kdePackages.plasma-bigscreen ]
                else
                  [ pkgs.kdePackages.plasma-bigscreen ];

              services.displayManager.defaultSession = lib.mkIf replacePlasma (
                lib.mkForce "plasma-bigscreen-wayland"
              );

              environment.etc = lib.mkIf replacePlasma {
                "xdg/kscreenlockerrc".text = ''
                  [Daemon]
                  Autolock=false
                  LockOnResume=false
                '';
              };
            }
          ]
          ++ lib.optionals isHeadless [
            (import ./headless.nix { inherit lib pkgs cfg; })
          ]
        )
      )
    ];

  meta = {
    name = "bigscreen";

    dependencies = lib.optionals isHeadless [
      {
        modules = [ "kde-virtual-session" ];
      }
    ];
  };
}
