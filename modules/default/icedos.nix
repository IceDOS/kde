{ icedosLib, lib, ... }:

{
  inputs.plasma-manager = {
    url = "github:nix-community/plasma-manager";
    inputs.nixpkgs.follows = "nixpkgs";
    inputs.home-manager.follows = "home-manager";
  };

  options.icedos.desktop.kde =
    let
      inherit (icedosLib) mkStrListOption;
      inherit (lib) importTOML;

      inherit ((importTOML ./config.toml).icedos.desktop.kde)
        excludeDefaultPackages
        ;
    in
    {
      excludeDefaultPackages = mkStrListOption { default = excludeDefaultPackages; };
    };

  outputs.nixosModules =
    { inputs, ... }:
    [
      (
        {
          config,
          icedosLib,
          pkgs,
          ...
        }:

        let
          inherit (config.icedos.desktop.kde) excludeDefaultPackages;
          inherit (icedosLib.pkgs) mapper;
        in
        {
          services.desktopManager.plasma6.enable = true;

          # FHS apps (e.g. Signal) ship bundled glib without libsecret; add the
          # store paths session-wide (read-only, so no LD_LIBRARY_PATH hijack).
          environment.sessionVariables.LD_LIBRARY_PATH = [
            "${pkgs.glib.out}/lib"
            "${pkgs.libsecret}/lib"
          ];

          environment.plasma6.excludePackages =
            (with pkgs.kdePackages; [
              discover # KDE store
              elisa # Music player
              gwenview # Image viewer
              kate # Text editor
              khelpcenter # Help center
              konsole # Terminal
              ktexteditor # Text edit framework
              kwin-x11 # X11 session of kwin
              milou # Search engine app
              okular # Document viewer
              qrca # Barcode scanner
            ])
            ++ (mapper pkgs.kdePackages excludeDefaultPackages);

          home-manager.sharedModules = [
            (
              {
                config,
                lib,
                pkgs,
                ...
              }:

              {
                imports = [
                  inputs.plasma-manager.homeModules.plasma-manager
                ];

                programs.plasma.enable = true;

                # plasma-apply-lookandfeel (stylix + plasma-manager activations)
                # needs XDG_MENU_PREFIX to find plasma-applications.menu.
                home.activation.icedosXdgMenuPrefix =
                  lib.hm.dag.entryBefore [ "stylixLookAndFeel" "icedosPlasmaApply" ]
                    ''
                      export XDG_MENU_PREFIX="plasma-"
                    '';

                # run_all.sh runs at login; re-run it on every rebuild so
                # panel/theme changes land without a relogin.
                home.activation.icedosPlasmaApply = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                  rd="/run/user/$(${pkgs.coreutils}/bin/id -u)"
                  bus="$rd/bus"
                  run_all="${config.xdg.dataHome}/plasma-manager/run_all.sh"

                  if [ -S "$bus" ] && [ -x "$run_all" ] \
                    && XDG_RUNTIME_DIR="$rd" DBUS_SESSION_BUS_ADDRESS="unix:path=$bus" \
                       /run/current-system/sw/bin/qdbus org.kde.plasmashell >/dev/null 2>&1; then
                    $DRY_RUN_CMD env PATH="/run/current-system/sw/bin:$PATH" \
                      XDG_RUNTIME_DIR="$rd" DBUS_SESSION_BUS_ADDRESS="unix:path=$bus" "$run_all" || true
                  fi
                '';
              }
            )
          ];
        }
      )
    ];

  meta = {
    name = "default";

    dependencies = [
      {
        modules = [
          "desktop-session"
          "focus"
          "icons"
          "keyboard"
          "panel"
          "power"
          "screen-edges"
          "shortcuts"
          "splash-screen"
          "wallpaper"
          "window-decorations"
        ];
      }

      {
        url = "github:icedos/desktop";
        modules = [ "plm" ];
      }
    ];
  };
}
