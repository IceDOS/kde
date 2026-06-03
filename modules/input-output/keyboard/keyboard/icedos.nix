{ lib, ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      (
        { config, ... }:
        let
          inherit (config.icedos.desktop) keyboardLayouts;
          inherit (lib) mkIf;
        in
        {
          home-manager.sharedModules = [
            (mkIf (keyboardLayouts != [ ]) {
              programs.plasma.input.keyboard = {
                layouts = map (layout: { inherit layout; }) keyboardLayouts;
                options = [ "grp:win_space_toggle" ];
              };
            })
          ];
        }
      )
    ];

  meta.name = "keyboard";
}
