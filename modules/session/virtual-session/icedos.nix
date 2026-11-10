{ icedosLib, lib, ... }:

{
  options.icedos.desktop.kde.virtual-session = import ./options.nix {
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
          cfg = config.icedos.desktop.kde.virtual-session;
          headless = config.icedos.applications.sunshine-headless;
        in
        {
          icedos.applications.sunshine-headless.compositors.kwin = import ./scripts.nix {
            inherit pkgs lib;
            inherit (cfg) home;
          };

          icedos.applications.sunshine-headless.apps = lib.optional cfg.publishDesktop {
            name = cfg.appName;
            compositor = "kwin";
            command = [
              "plasmashell"
              "--no-respawn"
            ];
            packages = [ pkgs.kdePackages.plasma-workspace ];
          };

          assertions = [
            {
              assertion = lib.all (app: app.compositor != "kwin" || !(app.steamMode || app.shim)) headless.apps;
              message = "icedos.applications.sunshine-headless.apps entries with compositor = \"kwin\" cannot set steamMode or shim; those need gamescope.";
            }
          ];
        }
      )
    ];

  meta = {
    name = "kde-virtual-session";

    dependencies = [
      {
        url = "github:icedos/apps";
        modules = [
          "sunshine-headless"
        ];
      }
    ];
  };
}
