{ icedosLib, lib, ... }:

{
  options.icedos.desktop.kde.panel =
    let
      inherit (icedosLib)
        mkAttrsOption
        mkBoolOption
        mkEitherOption
        mkEnumOption
        mkIntBetweenOption
        mkStrListOption
        ;

      inherit (lib) importTOML types;

      inherit ((importTOML ./config.toml).icedos.desktop.kde.panel)
        autohide
        favorites
        floating
        height
        location
        opacity
        screen
        widgets
        ;
    in
    {
      applets = mkAttrsOption { default = { }; };
      autohide = mkBoolOption { default = autohide; };
      favorites = mkStrListOption { default = favorites; };
      floating = mkBoolOption { default = floating; };

      height = mkIntBetweenOption {
        path = "icedos.desktop.kde.panel.height";
        source = ./config.toml;
        default = height;
      } 1 1000;

      location =
        mkEnumOption
          {
            path = "icedos.desktop.kde.panel.location";
            source = ./config.toml;
            default = location;
          }
          [
            "top"
            "bottom"
            "left"
            "right"
            "floating"
          ];

      opacity =
        mkEnumOption
          {
            path = "icedos.desktop.kde.panel.opacity";
            source = ./config.toml;
            default = opacity;
          }
          [
            "adaptive"
            "opaque"
            "translucent"
          ];

      screen = mkEitherOption { default = screen; } types.str types.int;
      widgets = mkStrListOption { default = widgets; };
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        { config, lib, ... }:
        let
          inherit (lib) optionals;

          inherit (config.icedos.desktop.kde.panel)
            applets
            autohide
            floating
            height
            location
            opacity
            screen
            widgets
            ;

          hiding = if autohide then "autohide" else "none";

          opacityMap =
            {
              adaptive = 0;
              opaque = 1;
              translucent = 2;
            }
            .${opacity};

          resolved = map (id: applets.${id} or id) widgets;
        in
        {
          icedos.system.tips.list = [
            "Reorder what sits in your panel with widgets under [icedos.desktop.kde.panel]."
            "Move the panel to the top, left or right with location under [icedos.desktop.kde.panel]."
            "Make the panel thicker or thinner with height under [icedos.desktop.kde.panel]."
          ]
          ++ optionals autohide [
            "Your panel hides itself; push the mouse to that edge of the screen to bring it back."
          ]
          ++ optionals floating [
            "Your panel floats with a gap around it; set floating to false under [icedos.desktop.kde.panel] to dock it."
          ]
          ++ optionals (opacity == "adaptive") [
            "Your panel turns solid when a window reaches it and clear when the desktop is showing."
          ]
          ++ optionals (opacity == "translucent") [
            "Your panel is see-through; set opacity to opaque under [icedos.desktop.kde.panel] for a solid one."
          ];

          home-manager.sharedModules = [
            (
              { config, ... }:

              {
                programs.plasma.panels = [
                  {
                    inherit
                      floating
                      height
                      hiding
                      location
                      opacity
                      screen
                      ;

                    widgets = resolved;
                  }
                ];

                # plasma-manager's desktop-scripting property never reaches live
                # PanelView (#551). Write panelOpacity directly by containment id.
                programs.plasma.startup.startupScript."icedos_panel_opacity" = {
                  priority = 3;
                  runAlways = true;
                  text = ''
                    want=${toString opacityMap}
                    changed=0
                    ids=$(qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript 'print(panels().map(function(p){return p.id;}).join(" "))' 2>/dev/null)

                    set -f
                    for id in $ids; do
                      [ -n "$id" ] || continue
                      cur=$(kreadconfig6 --file plasmashellrc --group PlasmaViews --group "Panel $id" --key panelOpacity)
                      if [ "$cur" != "$want" ]; then
                        kwriteconfig6 --file plasmashellrc --group PlasmaViews --group "Panel $id" --key panelOpacity "$want"
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

  meta = {
    name = "panel";

    dependencies = [
      {
        modules = [
          "panel-digitalclock"
          "panel-icontasks"
          "panel-lock-logout"
          "panel-pager"
          "panel-spacer"
          "panel-systemtray"
        ];
      }
    ];
  };
}
