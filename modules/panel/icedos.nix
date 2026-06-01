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
        in
        {
          home-manager.sharedModules = [
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
            }
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
