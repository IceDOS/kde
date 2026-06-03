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
          plainColor = concatStringsSep "," (map toString (icedosLib.color.hexToRgbInts colorHex));
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
