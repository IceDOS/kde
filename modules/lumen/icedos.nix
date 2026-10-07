{ icedosLib, lib, ... }:

{
  options.icedos.desktop.kde.lumen =
    let
      inherit (icedosLib)
        mkBoolOption
        mkFloatBetweenOption
        mkIntBetweenOption
        mkNumberOption
        mkStrOption
        mkSubmoduleListOption
        ;

      inherit (lib) importTOML;

      cfg = (importTOML ./config.toml).icedos.desktop.kde.lumen;
      path = "icedos.desktop.kde.lumen";

      pointOptions = {
        time = mkStrOption { default = ""; };
        brightness = mkNumberOption { default = 50; };
      };
    in
    {
      widget = mkBoolOption { default = cfg.widget; };
      tray = mkBoolOption { default = cfg.tray; };

      interval = mkIntBetweenOption {
        path = "${path}.interval";
        source = ./config.toml;
        default = cfg.interval;
      } 10 3600;

      latitude = mkFloatBetweenOption {
        path = "${path}.latitude";
        source = ./config.toml;
        default = cfg.latitude;
      } (-90.0) 90.0;

      longitude = mkFloatBetweenOption {
        path = "${path}.longitude";
        source = ./config.toml;
        default = cfg.longitude;
      } (-180.0) 180.0;

      minBrightness = mkIntBetweenOption {
        path = "${path}.minBrightness";
        source = ./config.toml;
        default = cfg.minBrightness;
      } 0 100;

      tolerance = mkNumberOption { default = cfg.tolerance; };

      # Widget edits override points and monitors until "Reset to defaults".
      points = mkSubmoduleListOption { default = cfg.points; } pointOptions;

      monitors = mkSubmoduleListOption { default = cfg.monitors; } {
        label = mkStrOption { default = ""; };
        enable = mkBoolOption { default = true; };
        scale = mkNumberOption { default = 1.0; };
        offset = mkNumberOption { default = 0; };
        points = mkSubmoduleListOption { default = [ ]; } pointOptions;
      };
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
          cfg = config.icedos.desktop.kde.lumen;
          plasma = config.services.desktopManager.plasma6.enable;
          usesSun = lib.any (p: lib.hasPrefix "sun" p.time) (
            cfg.points ++ lib.concatMap (m: m.points) cfg.monitors
          );

          runtimeConfig = pkgs.writeText "lumen.json" (
            builtins.toJSON {
              inherit (cfg)
                interval
                latitude
                longitude
                minBrightness
                tolerance
                points
                monitors
                ;
            }
          );

          lumenPkg = pkgs.python3Packages.buildPythonApplication {
            pname = "lumen";
            version = "0.1.0";
            pyproject = true;
            src = ./src;
            build-system = [ pkgs.python3Packages.setuptools ];
            nativeCheckInputs = [ pkgs.python3Packages.pytestCheckHook ];
            # One list element per argv word; wrapProgram does not split them.
            makeWrapperArgs = [
              "--prefix"
              "PATH"
              ":"
              (lib.makeBinPath [
                pkgs.ddcutil
                pkgs.systemd
              ])
              "--set-default"
              "LUMEN_CONFIG"
              "${runtimeConfig}"
            ];
            meta = {
              description = "Scheduled per-monitor brightness for KDE Plasma";
              mainProgram = "lumen";
            };
          };

          lumenPlasmoid = pkgs.stdenvNoCC.mkDerivation {
            pname = "lumen-plasmoid";
            version = "0.1.0";
            src = ./plasmoid;
            dontConfigure = true;
            dontBuild = true;
            installPhase = ''
              runHook preInstall
              dst="$out/share/plasma/plasmoids/org.icedos.lumen"
              mkdir -p "$dst"
              cp -r ./* "$dst/"
              substituteInPlace "$dst/metadata.json" \
                --replace-fail '@tray@' ${lib.boolToString cfg.tray}
              substituteInPlace "$dst/contents/ui/main.qml" \
                --replace-fail '@lumen@' '${lumenPkg}/bin/lumen'
              runHook postInstall
            '';
            meta.description = "lumen KDE Plasma 6 widget";
          };
        in
        lib.mkIf plasma {
          # ddcutil opens /dev/i2c-* from the user service; i2c-dev and seat access come from here.
          hardware.i2c.enable = lib.mkDefault true;

          warnings = lib.optional (usesSun && cfg.latitude == 0.0 && cfg.longitude == 0.0) ''
            icedos.desktop.kde.lumen uses sunrise/sunset points but latitude and longitude are 0,
            so sun times are computed for the Gulf of Guinea. Set your location.
          '';

          environment.systemPackages = [ lumenPkg ];

          home-manager.sharedModules = [
            {
              home.packages = lib.optional cfg.widget lumenPlasmoid;

              # Reads and writes the panels over DDC, so it lives and dies with the graphical session.
              systemd.user.services.lumen = {
                Unit = {
                  Description = "lumen: scheduled monitor brightness";
                  PartOf = [ "graphical-session.target" ];
                  After = [ "graphical-session.target" ];
                };

                Service = {
                  ExecStart = "${lumenPkg}/bin/lumen run";
                  Restart = "on-failure";
                  RestartSec = 5;
                };

                Install.WantedBy = [ "graphical-session.target" ];
              };
            }
          ];

          icedos.system.toolset.commands = [
            {
              command = "brightness";
              bin = "${lumenPkg}/bin/lumen";
              help = "scheduled monitor brightness: status, set, pause, resume";
            }
          ];

          icedos.system.tips.list = [
            "Run 'icedos brightness status' to see each monitor's scheduled brightness."
            "Moving a monitor's brightness by hand pauses its schedule until the next point."
          ];
        }
      )
    ];

  meta.name = "lumen";
}
