{ icedosLib, lib, ... }:

{
  options.icedos.desktop.kde.window-borders =
    let
      inherit (icedosLib) mkIntBetweenOption mkStrListOption mkStrOption;
      inherit (lib) importTOML;

      inherit ((importTOML ./config.toml).icedos.desktop.kde.window-borders)
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

                hasNewline = s: lib.hasInfix "\n" s || lib.hasInfix "\r" s;

                # KConfig stores lists as comma-separated, escaped values;
                # the effect reads them back via
                # readEntry("ExcludeClasses", QStringList()). Escape `\` and `,`
                # so entries containing them survive the round-trip.
                escapedExclude = map (e: lib.replaceStrings [ "\\" "," ] [ "\\\\" "\\," ] e) excludeClasses;
              in
              {
                programs.plasma.configFile.kwinrc.Plugins."icedos-window-bordersEnabled" = true;

                xdg.configFile."icedos-window-bordersrc".text = generators.toINI { } {
                  General = {
                    BorderWidth = toString borderWidth;
                    BorderRadius = toString borderRadius;
                    ActiveColor = resolvedActive;
                    InactiveColor = resolvedInactive;
                    ExcludeClasses = concatStringsSep "," escapedExclude;
                  };
                };

                # The values above flow verbatim into the KConfig INI via
                # generators.toINI; a newline would inject arbitrary keys.
                assertions = [
                  {
                    assertion = !hasNewline resolvedActive;
                    message = "icedos.desktop.kde.window-borders.activeColor must not contain newlines (would corrupt the KConfig file).";
                  }
                  {
                    assertion = !hasNewline resolvedInactive;
                    message = "icedos.desktop.kde.window-borders.inactiveColor must not contain newlines (would corrupt the KConfig file).";
                  }
                  {
                    assertion = builtins.all (e: !hasNewline e) excludeClasses;
                    message = "icedos.desktop.kde.window-borders.excludeClasses entries must not contain newlines (would corrupt the KConfig file).";
                  }
                ];
              }
            )
          ];
        }
      )
    ];

  meta.name = "window-borders";
}
