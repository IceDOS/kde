{ icedosLib, lib, ... }:

{
  options.icedos.desktop.kde.no-titlebar =
    let
      inherit (icedosLib) mkStrListOption;
      inherit (lib) readFile;

      inherit ((fromTOML (readFile ./config.toml)).icedos.desktop.kde.no-titlebar)
        excludeClasses
        ;
    in
    {
      excludeClasses = mkStrListOption { default = excludeClasses; };
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          inherit (config.icedos.desktop.kde.no-titlebar) excludeClasses;
          inherit (lib) concatMapStringsSep;

          jsArray = "[" + concatMapStringsSep ", " (c: ''"${c}"'') excludeClasses + "]";

          script = pkgs.runCommandLocal "kwin-no-titlebar" { } ''
            dir="$out/share/kwin/scripts/icedos-no-titlebar"
            mkdir -p "$dir/contents/code"
            cp ${./metadata.json} "$dir/metadata.json"
            cp ${
              pkgs.replaceVars ./main.js {
                EXCLUDE_CLASSES = jsArray;
              }
            } "$dir/contents/code/main.js"
          '';
        in
        {
          environment.systemPackages = [ script ];

          home-manager.sharedModules = [
            {
              programs.plasma.configFile.kwinrc.Plugins."icedos-no-titlebarEnabled" = true;
            }
          ];
        }
      )
    ];

  meta.name = "no-titlebar";
}
