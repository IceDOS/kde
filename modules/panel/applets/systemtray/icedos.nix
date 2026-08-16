{ icedosLib, lib, ... }:

{
  options.icedos.desktop.kde.panel.system-tray =
    let
      inherit (lib) importTOML;

      inherit ((importTOML ./config.toml).icedos.desktop.kde.panel.system-tray)
        disabledApplets
        knownApplets
        ;
    in
    {
      # Full set of tray applets the framework manages (plasma's knownItems).
      knownApplets = icedosLib.mkStrListOption { default = knownApplets; };

      # Applet plugin IDs removed from enabled set but kept in knownItems
      # (plasma's "Never show (disabled)" state).
      disabledApplets = icedosLib.mkStrListOption { default = disabledApplets; };
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        { config, lib, ... }:
        let
          systemTray = config.icedos.desktop.kde.panel.system-tray;
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
                # plasma-manager can't keep tray visibility in plasma 6.4 nested
                # containment (#535). Subtract disabled applets from live extraItems.
                programs.plasma.startup.startupScript."icedos_systemtray" = {
                  priority = 3;
                  runAlways = true;
                  text = ''
                    disabled="${disabled}"
                    file=plasma-org.kde.plasma.desktop-appletsrc
                    changed=0
                    ids=$(qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript 'var o=[];panels().forEach(function(p){p.widgets("org.kde.plasma.systemtray").forEach(function(w){o.push(p.id+":"+w.id);});});print(o.join(" "));' 2>/dev/null)

                    set -f
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
                    set +f

                    if [ "$changed" = 1 ]; then
                      rf=${config.xdg.dataHome}/plasma-manager/services_to_restart
                      case "$(cat "$rf" 2>/dev/null)" in
                        *plasma-plasmashell*) : ;;
                        *) echo plasma-plasmashell >> "$rf" ;;
                      esac
                    fi
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
