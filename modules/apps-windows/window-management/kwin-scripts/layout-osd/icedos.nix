{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      (
        { pkgs, ... }:
        let
          script = pkgs.runCommandLocal "kwin-layout-osd" { } ''
            dir="$out/share/kwin/scripts/icedos-layout-osd"
            mkdir -p "$dir/contents/code"
            cp ${./metadata.json} "$dir/metadata.json"
            cp ${./main.js} "$dir/contents/code/main.js"
          '';
        in
        {
          environment.systemPackages = [ script ];

          home-manager.sharedModules = [
            { programs.plasma.configFile.kwinrc.Plugins."icedos-layout-osdEnabled" = true; }
          ];
        }
      )
    ];

  meta.name = "layout-osd";
}
