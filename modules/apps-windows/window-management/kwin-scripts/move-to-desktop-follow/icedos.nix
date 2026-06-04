{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      (
        { pkgs, lib, ... }:
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
              programs.plasma = {
                configFile.kwinrc.Plugins."move-to-desktop-followEnabled" = true;

                # Move the active window to desktop N and follow it there.
                # mkDefault so the user's config.toml can still override.
                shortcuts.kwin = {
                  MoveWindowToDesktopAndFollow1 = lib.mkDefault "Meta+!";
                  MoveWindowToDesktopAndFollow2 = lib.mkDefault "Meta+@";
                  MoveWindowToDesktopAndFollow3 = lib.mkDefault "Meta+#";
                  MoveWindowToDesktopAndFollow4 = lib.mkDefault "Meta+$";
                  MoveWindowToDesktopAndFollow5 = lib.mkDefault "Meta+%";
                  MoveWindowToDesktopAndFollow6 = lib.mkDefault "Meta+^";
                  MoveWindowToDesktopAndFollow7 = lib.mkDefault "Meta+&";
                  MoveWindowToDesktopAndFollow8 = lib.mkDefault "Meta+*";
                  MoveWindowToDesktopAndFollow9 = lib.mkDefault "Meta+(";
                  MoveWindowToDesktopAndFollow10 = lib.mkDefault "Meta+)";
                };
              };
            }
          ];
        }
      )
    ];

  meta.name = "move-to-desktop-follow";
}
