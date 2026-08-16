{ lib, ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      {
        home-manager.sharedModules = [
          (
            { config, pkgs, ... }:
            let
              inherit (config) stylix;

              iconTheme = if stylix.polarity == "light" then stylix.icons.light else stylix.icons.dark;

              # Tela tray icons are edge-to-edge (oversized under scaleIconsToFit);
              # inset each by 0.875 via pad-icon.py (viewBox rewrite).
              paddedIcons =
                map
                  (name: {
                    subdir = "status";
                    inherit name;
                  })
                  [
                    "microphone-sensitivity-high-symbolic"
                    "microphone-sensitivity-low-symbolic"
                    "microphone-sensitivity-medium-symbolic"
                    "microphone-sensitivity-muted-symbolic"
                    "microphone-sensitivity-none-symbolic"
                    "notifications-disabled-symbolic"
                    "notifications-new-symbolic"
                    "notifications-symbolic"
                  ];

              paddedTelaIcons =
                pkgs.runCommandLocal "tela-padded-icons" { nativeBuildInputs = [ pkgs.python3 ]; }
                  (
                    lib.concatMapStringsSep "\n" (icon: ''
                      mkdir -p "$out/symbolic/${icon.subdir}"
                      python3 ${./lib/pad-icon.py} 0.875 \
                        "${pkgs.tela-icon-theme}/share/icons/${iconTheme}/symbolic/${icon.subdir}/${icon.name}.svg" \
                        "$out/symbolic/${icon.subdir}/${icon.name}.svg"
                    '') paddedIcons
                  );

              iconOverride = lib.listToAttrs (
                map (icon: {
                  name = ".local/share/icons/${iconTheme}/symbolic/${icon.subdir}/${icon.name}.svg";
                  value.source = "${paddedTelaIcons}/symbolic/${icon.subdir}/${icon.name}.svg";
                }) paddedIcons
              );
            in
            lib.mkIf stylix.icons.enable {
              programs.plasma.workspace.iconTheme = iconTheme;

              home.file = lib.mkIf (lib.hasPrefix "Tela" iconTheme) iconOverride;
            }
          )
        ];
      }
    ];

  meta.name = "icons";
}
