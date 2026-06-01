{ lib, ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      {
        home-manager.sharedModules = [
          (
            { config, ... }:
            lib.mkIf (config.stylix.enable && config.stylix.icons.enable) {
              programs.plasma.workspace.iconTheme =
                if config.stylix.polarity == "light" then config.stylix.icons.light else config.stylix.icons.dark;
            }
          )
        ];
      }
    ];

  meta.name = "icons";
}
