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

      inherit (lib) readFile types;

      inherit ((fromTOML (readFile ./config.toml)).icedos.desktop.kde.panel)
        floating
        height
        location
        opacity
        screen
        widgets
        ;
    in
    {
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

      # "all" or a 0-based monitor index.
      screen = mkEitherOption { default = screen; } types.str types.int;

      height = mkIntBetweenOption {
        path = "icedos.desktop.kde.panel.height";
        source = ./config.toml;
        default = height;
      } 1 1000;

      floating = mkBoolOption { default = floating; };

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

      widgets = mkStrListOption { default = widgets; };
      applets = mkAttrsOption { default = { }; };
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        { config, ... }:
        let
          inherit (config.icedos.desktop.kde.panel)
            applets
            floating
            height
            location
            opacity
            screen
            widgets
            ;

          resolved = map (id: applets.${id} or id) widgets;

          opacityInt =
            ({
              adaptive = 0;
              opaque = 1;
              translucent = 2;
            }).${opacity};
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
                    want=${toString opacityInt}
                    changed=0
                    ids=$(qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript 'print(panels().map(function(p){return p.id;}).join(" "))' 2>/dev/null)

                    for id in $ids; do
                      [ -n "$id" ] || continue
                      cur=$(kreadconfig6 --file plasmashellrc --group PlasmaViews --group "Panel $id" --key panelOpacity)
                      if [ "$cur" != "$want" ]; then
                        kwriteconfig6 --file plasmashellrc --group PlasmaViews --group "Panel $id" --key panelOpacity "$want"
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
