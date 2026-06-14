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

              # Several of Tela's symbolic tray icons are drawn edge-to-edge (no internal
              # margin), so the mic recording indicator, the notifications/DnD bell and the
              # lock/logout power button render oversized next to their padded neighbours
              # under the tray's scaleIconsToFit. We inset each by 0.875 (~1px margin on the
              # 16px canvas) and drop the result over the stock icon: XDG unions same-named
              # themes across base dirs with the user dir winning, so only these icons change.
              #
              # The padded SVGs are produced by Nix from Tela's own originals (pad-icon.py
              # rewrites the viewBox) — no hand-edited artwork in the repo. system-shutdown
              # ships in both symbolic/actions and symbolic/status with different markup, and
              # KDE resolves it via the earlier symbolic/actions entry, so pad both.
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
            lib.mkIf (stylix.enable && stylix.icons.enable) {
              programs.plasma.workspace.iconTheme = iconTheme;

              home.file = lib.mkIf (lib.hasPrefix "Tela" iconTheme) iconOverride;
            }
          )
        ];
      }
    ];

  meta.name = "icons";
}
