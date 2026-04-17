{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      {
        services.desktopManager.plasma6.enable = true;
      }
    ];

  meta = {
    name = "default";

    optionalDependencies = [
      {
        url = "github:icedos/desktop";
        modules = [ "sddm" ];
      }
    ];
  };
}
