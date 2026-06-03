{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      (
        { pkgs, ... }:
        let
          script = pkgs.runCommandLocal "kwin-move-to-desktop-follow" { } ''
            dir="$out/share/kwin/scripts/move-to-desktop-follow"
            mkdir -p "$dir/contents/code"
            cp ${./metadata.json} "$dir/metadata.json"
            cp ${./main.js} "$dir/contents/code/main.js"
          '';
        in
        {
          environment.systemPackages = [ script ];

          home-manager.sharedModules = [
            {
              programs.plasma.configFile.kwinrc.Plugins."move-to-desktop-followEnabled" = true;
            }
          ];
        }
      )
    ];

  meta.name = "move-to-desktop-follow";
}
