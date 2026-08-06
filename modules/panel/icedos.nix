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
        { config, ... }:
        let
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

                # plasma-manager applies panel opacity only via the `panel.opacity`
                # desktop-scripting property, which never reaches the live PanelView,
                # so panelOpacity is never written to plasmashellrc and the panel stays
                # "adaptive" (upstream plasma-manager #551). Write panelOpacity directly
                # for the live panels, keyed by their runtime containment id. Runs inside
                # run_all after the panel-creation script (priority 2); the single
                # plasmashell restart at the end of run_all applies it. runAlways so it
                # re-fires when panel ids change (runAlways ignores restartServices, hence
                # the manual services_to_restart queue), idempotent otherwise.
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
