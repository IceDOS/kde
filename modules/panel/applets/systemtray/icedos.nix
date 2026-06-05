{ icedosLib, lib, ... }:

{
  options.icedos.desktop.kde.panel.systemTray =
    let
      inherit (lib) readFile;

      inherit ((fromTOML (readFile ./config.toml)).icedos.desktop.kde.panel.systemTray)
        disabledApplets
        knownApplets
        ;
    in
    {
      # Full set of tray applets the framework manages (plasma's knownItems).
      knownApplets = icedosLib.mkStrListOption { default = knownApplets; };

      # Applet plugin IDs (e.g. "org.kde.plasma.clipboard") removed from the
      # enabled set (extraItems) while kept in knownItems — plasma's
      # "Never show (disabled)" entry state.
      disabledApplets = icedosLib.mkStrListOption { default = disabledApplets; };
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        { config, lib, ... }:
        let
          inherit (config.icedos.desktop.kde.panel) systemTray;
          disabled = lib.concatStringsSep " " systemTray.disabledApplets;
        in
        {
          icedos.desktop.kde.panel.applets."org.kde.plasma.systemtray" = {
            name = "org.kde.plasma.systemtray";
            config.General = {
              scaleIconsToFit = true;
              knownItems = systemTray.knownApplets;
            };
          };

          home-manager.sharedModules = [
            (
              { config, ... }:

              {
                # plasma-manager (post-#501) can't keep tray item visibility in
                # plasma 6.4's nested containment (upstream plasma-manager #535), and
                # forcing extraItems re-enables disabled applets on every run_all.
                # Instead subtract disabledApplets from the live extraItems straight in
                # appletsrc — keyed by the runtime systray applet id, like the
                # panel-opacity workaround — and let the single run_all plasmashell
                # restart reload it. runAlways re-fires every rebuild (ignores
                # restartServices, hence the manual services_to_restart queue);
                # idempotent: a no-op once converged and when disabledApplets is empty.
                programs.plasma.startup.startupScript."icedos_systemtray" = {
                  priority = 3;
                  runAlways = true;
                  text = ''
                    disabled="${disabled}"
                    file=plasma-org.kde.plasma.desktop-appletsrc
                    changed=0
                    ids=$(qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript 'var o=[];panels().forEach(function(p){p.widgets("org.kde.plasma.systemtray").forEach(function(w){o.push(p.id+":"+w.id);});});print(o.join(" "));' 2>/dev/null)

                    for pair in $ids; do
                      cid=''${pair%%:*}
                      aid=''${pair##*:}
                      [ -n "$cid" ] && [ -n "$aid" ] || continue

                      ex=$(kreadconfig6 --file "$file" --group Containments --group "$cid" --group Applets --group "$aid" --group General --key extraItems)
                      kn=$(kreadconfig6 --file "$file" --group Containments --group "$cid" --group Applets --group "$aid" --group General --key knownItems)

                      # keep disabled applets in knownItems so they show as "disabled"
                      # rather than vanish (and aren't re-added to extraItems as new).
                      nkn=$kn
                      for d in $disabled; do
                        case ",$nkn," in
                          *",$d,"*) : ;;
                          *) nkn="''${nkn:+$nkn,}$d" ;;
                        esac
                      done

                      # drop disabled applets from extraItems, leave everything else
                      # (including plasma-discovered applets) untouched.
                      nex=$ex
                      if [ -n "$ex" ]; then
                        nex=""
                        oIFS=$IFS
                        IFS=,
                        for it in $ex; do
                          case " $disabled " in
                            *" $it "*) : ;;
                            *) nex="''${nex:+$nex,}$it" ;;
                          esac
                        done
                        IFS=$oIFS
                      fi

                      if [ "$nex" != "$ex" ] || [ "$nkn" != "$kn" ]; then
                        kwriteconfig6 --file "$file" --group Containments --group "$cid" --group Applets --group "$aid" --group General --key extraItems "$nex"
                        kwriteconfig6 --file "$file" --group Containments --group "$cid" --group Applets --group "$aid" --group General --key knownItems "$nkn"
                        changed=1
                      fi
                    done

                    [ "$changed" = 1 ] && echo plasma-plasmashell >> ${config.xdg.dataHome}/plasma-manager/services_to_restart
                    true
                  '';
                };
              }
            )
          ];
        }
      )
    ];

  meta.name = "panel-systemtray";
}
