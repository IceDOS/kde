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
      inherit (lib) readFile;

      inherit ((fromTOML (readFile ./config.toml)).icedos.desktop.kde)
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
          nix.settings = {
            substituters = [ "https://cache.garnix.io" ];
            trusted-public-keys = [
              "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
            ];
          };

          services.desktopManager.plasma6.enable = true;

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
            {
              imports = [
                inputs.plasma-manager.homeModules.plasma-manager
              ];

              programs.plasma.enable = true;
            }
          ];
        }
      )
    ];

  meta = {
    name = "default";

    dependencies = [
      {
        modules = [
          "focus"
          "icons"
          "keyboard"
          "panel"
          "shortcuts"
          "splash-screen"
          "wallpaper"
          "window-decorations"
        ];
      }
    ];

    optionalDependencies = [
      {
        url = "github:icedos/desktop";
        modules = [ "plm" ];
      }
    ];
  };
}
