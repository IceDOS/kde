{
  pkgs,
  cfg,
  ...
}:

let
  bigscreenLauncher = pkgs.writeShellScript "plasma-bigscreen-headless-launcher" ''
    export XDG_CONFIG_DIRS="$HOME/.config/plasma-bigscreen:''${XDG_CONFIG_DIRS:-/etc/xdg}"

    QT_QPA_PLATFORM=offscreen ${pkgs.kdePackages.plasma-bigscreen}/bin/plasma-bigscreen-envmanager --apply-settings
    QT_QPA_PLATFORM=offscreen ${pkgs.kdePackages.plasma-bigscreen}/bin/plasma-bigscreen-inputhandler &
    ih_pid=$!

    ${pkgs.kdePackages.plasma-workspace}/bin/plasmashell --no-respawn -p org.kde.plasma.bigscreen
    kill "$ih_pid" 2>/dev/null
  '';
in
{
  icedos.applications.sunshine-headless.apps = [
    {
      name = cfg.appName;
      compositor = "kwin";
      command = [
        "${bigscreenLauncher}"
      ];
      env = {
        QT_ENABLE_GLYPH_CACHE_WORKAROUND = "1";
        PLASMA_INTEGRATION_USE_PORTAL = "1";
        PLASMA_PLATFORM = "mediacenter";
        QT_FILE_SELECTORS = "mediacenter";
        PLASMA_DEFAULT_SHELL = "org.kde.plasma.bigscreen";
        KWIN_IM_SHOW_ALWAYS = "1";
      };
      packages = [
        pkgs.kdePackages.plasma-bigscreen
        pkgs.kdePackages.plasma-workspace
        pkgs.kdePackages.kdeconnect-kde
      ];
    }
  ];
}
