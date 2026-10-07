{ icedosLib, lib, ... }:

{
  options.icedos.desktop.kde.vigor =
    let
      inherit (icedosLib)
        mkBoolOption
        mkEnumOption
        mkFloatBetweenOption
        mkIntBetweenOption
        mkNumberOption
        mkStrListOption
        mkStrOption
        mkSubmoduleListOption
        ;

      inherit (lib) importTOML;

      cfg = (importTOML ./config.toml).icedos.desktop.kde.vigor;
      path = "icedos.desktop.kde.vigor";

      diskOption = d: {
        idle = mkNumberOption { default = d.idle; };
        active = mkNumberOption { default = d.active; };
      };
    in
    {
      # Plasma 6 applet; tray decides whether it is enabled in the system tray by default.
      widget = mkBoolOption { default = cfg.widget; };
      tray = mkBoolOption { default = cfg.tray; };

      # Lets the widget's profile slider set CPU governor and boost when power-profiles-daemon has no CPU driver.
      tune = mkBoolOption { default = cfg.tune; };

      interval = mkIntBetweenOption {
        path = "${path}.interval";
        source = ./config.toml;
        default = cfg.interval;
      } 1 60;

      currency = mkStrOption { default = cfg.currency; };
      price = mkNumberOption { default = cfg.price; };
      surcharge = mkNumberOption { default = cfg.surcharge; };
      vat = mkNumberOption { default = cfg.vat; };

      # Local HH:MM ranges; a range may cross midnight.
      bands = mkSubmoduleListOption { default = cfg.bands; } {
        start = mkStrOption { default = ""; };
        end = mkStrOption { default = ""; };
        price = mkNumberOption { default = 0; };
      };

      psuEfficiency = mkFloatBetweenOption {
        path = "${path}.psuEfficiency";
        source = ./config.toml;
        default = cfg.psuEfficiency;
      } 0.5 1.0;

      baseWatts = mkNumberOption { default = cfg.baseWatts; };
      nicWatts = mkNumberOption { default = cfg.nicWatts; };
      standbyWatts = mkNumberOption { default = cfg.standbyWatts; };
      cpuIdleWatts = mkNumberOption { default = cfg.cpuIdleWatts; };
      cpuMaxWatts = mkNumberOption { default = cfg.cpuMaxWatts; };
      gpuIdleWatts = mkNumberOption { default = cfg.gpuIdleWatts; };
      gpuMaxWatts = mkNumberOption { default = cfg.gpuMaxWatts; };

      diskWatts = {
        nvme = diskOption cfg.diskWatts.nvme;
        ssd = diskOption cfg.diskWatts.ssd;
        hdd = diskOption cfg.diskWatts.hdd;
      };

      extraLoads = mkSubmoduleListOption { default = cfg.extraLoads; } {
        name = mkStrOption { default = ""; };
        watts = mkNumberOption { default = 0; };
      };

      # Same grammar as prime-agent meters.power.windows; checked by the assertions below.
      windows = mkStrListOption { default = cfg.windows; };
      componentWindow = mkStrOption { default = cfg.componentWindow; };

      plug = {
        type =
          mkEnumOption
            {
              path = "${path}.plug.type";
              source = ./config.toml;
              default = cfg.plug.type;
            }
            [
              "none"
              "shelly"
              "tasmota"
            ];

        host = mkStrOption { default = cfg.plug.host; };
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
          cfg = config.icedos.desktop.kde.vigor;
          widget = cfg.widget && config.services.desktopManager.plasma6.enable;
          nvidia = lib.elem "nvidia" config.services.xserver.videoDrivers;

          vigorPkg = pkgs.python3Packages.buildPythonApplication {
            pname = "vigor";
            version = "0.1.0";
            pyproject = true;
            src = ./src;
            build-system = [ pkgs.python3Packages.setuptools ];
            dependencies = [ pkgs.python3Packages.jeepney ];
            # pkexec and systemd-run need the absolute path the polkit rule below names.
            makeWrapperArgs = [
              "--set"
              "VIGOR_BIN"
              "${placeholder "out"}/bin/vigor"
              "--set"
              "VIGOR_TUNE"
              (if cfg.tune then "1" else "0")
            ];
            nativeCheckInputs = [ pkgs.python3Packages.pytestCheckHook ];
            meta = {
              description = "Per-component power draw and electricity cost meter";
              mainProgram = "vigor";
            };
          };

          runtimeConfig = pkgs.writeText "vigor.json" (
            builtins.toJSON {
              inherit (cfg)
                interval
                currency
                price
                surcharge
                vat
                bands
                psuEfficiency
                baseWatts
                nicWatts
                standbyWatts
                cpuIdleWatts
                cpuMaxWatts
                gpuIdleWatts
                gpuMaxWatts
                diskWatts
                extraLoads
                plug
                windows
                componentWindow
                ;
            }
          );

          # One-time move of the history and chosen profile kept under the old wattmeter name.
          migrate = pkgs.writeShellScript "vigor-migrate" ''
            old=/var/lib/wattmeter new=/var/lib/vigor
            [ -d "$old" ] && [ ! -e "$new/vigor.db" ] || exit 0
            for f in "$old"/wattmeter.db*; do
              [ -e "$f" ] && mv "$f" "$new/vigor.db''${f#"$old"/wattmeter.db}"
            done
            [ -e "$old/profile" ] && mv "$old/profile" "$new/profile"
            rmdir "$old" 2>/dev/null || true
          '';

          vigorPlasmoid = pkgs.stdenvNoCC.mkDerivation {
            pname = "vigor-plasmoid";
            version = "0.1.0";
            src = ./plasmoid;
            dontConfigure = true;
            dontBuild = true;
            installPhase = ''
              runHook preInstall
              dst="$out/share/plasma/plasmoids/org.icedos.vigor"
              mkdir -p "$dst"
              cp -r ./* "$dst/"
              substituteInPlace "$dst/metadata.json" \
                --replace-fail '@tray@' ${lib.boolToString cfg.tray}
              substituteInPlace "$dst/contents/ui/main.qml" \
                --replace-fail '@cat@' '${pkgs.coreutils}/bin/cat' \
                --replace-fail '@now@' '/run/vigor/now.json' \
                --replace-fail '@vigor@' '${vigorPkg}/bin/vigor'
              runHook postInstall
            '';
            meta.description = "vigor KDE Plasma 6 widget";
          };
        in
        {
          assertions = [
            {
              assertion =
                cfg.windows != [ ] && builtins.all (w: builtins.match "[1-9][0-9]*[smhdwM]" w != null) cfg.windows;
              message = ''
                icedos.desktop.kde.vigor.windows must be non-empty and each entry a positive
                integer followed by s, m, h, d, w or M (e.g. "15m", "24h", "1M"), got: ${builtins.concatStringsSep ", " cfg.windows}
              '';
            }
            {
              assertion = lib.elem cfg.componentWindow cfg.windows;
              message = "icedos.desktop.kde.vigor.componentWindow (${cfg.componentWindow}) must be one of windows.";
            }
          ];

          # Root so RAPL counters stay root-only; runs without a login so standby and SDDM time count too.
          systemd.services.vigor = {
            description = "vigor: power draw and electricity cost sampler";
            wantedBy = [ "multi-user.target" ];
            path = lib.optional nvidia config.hardware.nvidia.package.bin;

            serviceConfig = {
              # Reapplies the profile last picked in the widget; a missing state file is a no-op.
              # "+" runs the migration outside ProtectSystem, which would hide /var/lib/wattmeter.
              ExecStartPre = [ "+${migrate}" ] ++ lib.optional cfg.tune "-${vigorPkg}/bin/vigor tune restore";
              ExecStart = "${vigorPkg}/bin/vigor --config ${runtimeConfig} run";
              StateDirectory = "vigor";
              RuntimeDirectory = "vigor";
              RuntimeDirectoryMode = "0755";
              Restart = "on-failure";
              Nice = 10;
              ProtectSystem = "strict";
              ProtectHome = true;
              PrivateTmp = true;
              NoNewPrivileges = true;
              RestrictAddressFamilies = [
                "AF_UNIX"
                "AF_INET"
                "AF_INET6"
              ];
            };
          };

          environment.systemPackages = [ vigorPkg ];

          # prime-agent still writes its local-model leases under the old name.
          systemd.tmpfiles.rules = [ "L+ /run/wattmeter - - - - /run/vigor" ];

          # Only the exact tune command, only for a local active session; anything else still asks.
          security.polkit.extraConfig = lib.mkIf cfg.tune ''
            polkit.addRule(function (action, subject) {
              var bin = "${vigorPkg}/bin/vigor";
              if (action.id == "org.freedesktop.policykit.exec" &&
                  action.lookup("program") == bin &&
                  /^\S+ tune apply (power-saver|balanced|performance)$/.test(action.lookup("command_line")) &&
                  subject.local && subject.active) {
                return polkit.Result.YES;
              }
            });
          '';

          # Add via "Add Widgets", or pin "org.icedos.vigor" in icedos.desktop.kde.panel.widgets.
          home-manager.sharedModules = [
            { home.packages = lib.optional widget vigorPlasmoid; }
          ];

          icedos.system.toolset.commands = [
            {
              command = "power";
              bin = "${vigorPkg}/bin/vigor";
              help = "live power draw and electricity cost per component";
            }
          ];

          icedos.system.tips.list = [
            "Run 'icedos power' for live watts and electricity cost per component."
            "Set your tariff under [icedos.desktop.kde.vigor] (price, surcharge, vat, bands)."
          ]
          ++ lib.optionals widget [
            "The vigor widget's Sleep tab can keep the screen awake, block sleep, or schedule a shutdown."
            "The vigor widget lists the battery of every wireless mouse, keyboard, headset and controller UPower knows."
            (
              if cfg.tray then
                "vigor sits in the Plasma system tray. You can also add it to a panel as a widget."
              else
                "Add the vigor widget to a Plasma panel, or turn it on in the system tray settings."
            )
          ];
        }
      )
    ];

  meta.name = "vigor";
}
