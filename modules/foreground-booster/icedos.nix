{ lib, ... }: {
  outputs.nixosModules = { inputs, ... }: [
    (
      { config, pkgs, ... }:
      let
        inherit (config.boot.kernelPackages.kernel) version;
        inherit (lib) mkIf versionAtLeast;

        cgroupDmemSupported = versionAtLeast version "7.0";

        booster = (pkgs.extend inputs.jovian.overlays.default).plasma-foreground-booster;
      in
      mkIf cgroupDmemSupported {
        environment.systemPackages = [ booster ];

        home-manager.sharedModules = [
          {
            programs.plasma.configFile.kcgroupsrc = {
              "Foreground Booster" = {
                autostart = true;
              };
            };

            systemd.user.services.plasma-foreground-booster = {
              Unit = {
                Description = "Foreground app CPU weight booster";

                BindsTo = [ "plasma-kwin_wayland.service" ];
                After = [
                  "plasma-kwin_wayland.service"
                  "graphical-session.target"
                ];
                PartOf = "graphical-session.target";
              };

              Install.WantedBy = [ "plasma-workspace-wayland.target" ];

              Service = {
                Type = "dbus";
                BusName = "org.kde.foreground-booster";
                Restart = "on-failure";
                ExecStart = "${booster}/bin/foreground_booster";
                ExecCondition = "${pkgs.kdePackages.plasma-workspace}/bin/kde-systemd-start-condition --condition \"kcgroupsrc:Foreground Booster:autostart:true\"";
                Slice = "background.slice";
              };
            };
          }
        ];
      }
    )
  ];

  meta = {
    name = "foreground-booster";
    dependencies = [
      {
        url = "github:icedos/tweaks";
        modules = [ "dmem" ];
      }
      {
        url = "github:icedos/providers";
        modules = [ "jovian" ];
      }
    ];
  };
}
