{ ... }:

{
  inputs.plasma67-cache.url = "github:IceDBorn/plasma67-cache";

  outputs.nixosModules =
    { ... }:
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
        }
      )
    ];

  meta = {
    name = "default";

    optionalDependencies = [
      {
        url = "github:icedos/desktop";
        modules = [ "plm" ];
      }
    ];
  };
}
