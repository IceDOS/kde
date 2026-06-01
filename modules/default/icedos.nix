{ ... }:

{
  inputs.plasma67-cache.url = "github:IceDBorn/plasma67-cache";

  inputs.plasma-manager = {
    url = "github:nix-community/plasma-manager";
    inputs.nixpkgs.follows = "nixpkgs";
    inputs.home-manager.follows = "home-manager";
  };

  outputs.nixosModules =
    { inputs, ... }:
    [
      (
        {
          pkgs,
          ...
        }:
        {
          nix.settings = {
            substituters = [ "https://cache.garnix.io" ];
            trusted-public-keys = [
              "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
            ];
          };

          services.desktopManager.plasma6.enable = true;

          environment.plasma6.excludePackages = with pkgs.kdePackages; [
            discover # Flatpak search
            dolphin # File manager
            elisa # Music player
            gwenview # Image viewer
            kate # Advanced text editor
            khelpcenter # Help center
            konsole # Terminal
            ktexteditor # KTextEditor Framework
            milou # Dedicated search application built on top of Baloo
            okular # Document viewer
          ];

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
          "icons"
          "panel"
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
