{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      (
        {
          config,
          icedosLib,
          lib,
          ...
        }:
        let
          inherit (lib)
            concatStringsSep
            hasPrefix
            mkIf
            removePrefix
            ;

          globalWallpaper = config.icedos.desktop.wallpaper;
          isColor = hasPrefix "color:" globalWallpaper;
          isPath = !isColor && globalWallpaper != "";
          wallpaperPath = removePrefix "path:" globalWallpaper;
          colorHex = removePrefix "color:" globalWallpaper;

          # Accept "RRGGBB" and "#RRGGBB" (hexToRgbInts strips the "#" itself).
          validColor = builtins.match "#?[0-9a-fA-F]{6}" colorHex != null;

          plainColor = concatStringsSep "," (
            map toString (
              if validColor then
                icedosLib.color.hexToRgbInts colorHex
              else
                throw "icedos.desktop.wallpaper: color: expected RRGGBB or #RRGGBB, got \"${colorHex}\""
            )
          );
        in
        {
          home-manager.sharedModules = [
            (mkIf isPath {
              programs.plasma.workspace = {
                wallpaper = wallpaperPath;
                wallpaperFillMode = "preserveAspectCrop";
              };

              programs.plasma.kscreenlocker.appearance.wallpaper = wallpaperPath;
            })

            (mkIf isColor {
              programs.plasma.workspace.wallpaperPlainColor = plainColor;
              programs.plasma.kscreenlocker.appearance.wallpaperPlainColor = plainColor;
            })
          ];
        }
      )
    ];

  meta.name = "wallpaper";
}
