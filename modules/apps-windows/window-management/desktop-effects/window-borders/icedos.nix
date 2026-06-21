{ icedosLib, lib, ... }:

{
  options.icedos.desktop.kde.window-borders =
    let
      inherit (icedosLib) mkIntBetweenOption mkStrListOption mkStrOption;
      inherit (lib) readFile;

      inherit ((fromTOML (readFile ./config.toml)).icedos.desktop.kde.window-borders)
        activeColor
        borderRadius
        borderWidth
        excludeClasses
        inactiveColor
        ;
    in
    {
      borderWidth = mkIntBetweenOption {
        path = "icedos.desktop.kde.window-borders.borderWidth";
        source = ./config.toml;
        default = borderWidth;
      } 0 10;

      borderRadius = mkIntBetweenOption {
        path = "icedos.desktop.kde.window-borders.borderRadius";
        source = ./config.toml;
        default = borderRadius;
      } 0 20;

      activeColor = mkStrOption { default = activeColor; };
      inactiveColor = mkStrOption { default = inactiveColor; };
      excludeClasses = mkStrListOption { default = excludeClasses; };
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        { config, pkgs, ... }:
        let
          inherit (config.icedos.desktop.kde.window-borders)
            activeColor
            borderRadius
            borderWidth
            excludeClasses
            inactiveColor
            ;

          effect = pkgs.callPackage ./lib/package.nix { };
        in
        {
          environment.systemPackages = [ effect ];

          home-manager.sharedModules = [
            (
              { config, lib, ... }:
              let
                inherit (lib) concatStringsSep generators;

                colors = config.lib.stylix.colors or { };

                resolvedActive =
                  if activeColor != "" then
                    activeColor
                  else if colors ? base0D then
                    "#${colors.base0D}"
                  else
                    "#3daee9";

                resolvedInactive =
                  if inactiveColor != "" then
                    inactiveColor
                  else if colors ? base03 then
                    "#${colors.base03}"
                  else
                    "transparent";
              in
              {
                programs.plasma.configFile.kwinrc.Plugins."icedos-window-bordersEnabled" = true;

                xdg.configFile."icedos-window-bordersrc".text = generators.toINI { } {
                  General = {
                    BorderWidth = toString borderWidth;
                    BorderRadius = toString borderRadius;
                    ActiveColor = resolvedActive;
                    InactiveColor = resolvedInactive;
                    ExcludeClasses = concatStringsSep "," excludeClasses;
                  };
                };
              }
            )
          ];
        }
      )
    ];

  meta.name = "window-borders";
}
