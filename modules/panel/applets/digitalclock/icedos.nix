{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      {
        icedos.desktop.kde.panel.applets."org.kde.plasma.digitalclock" = {
          digitalClock = {
            date.enable = false;

            time = {
              showSeconds = "always";
              format = "24h";
            };

            font = {
              family = "Adwaita Mono";
              bold = true;
              weight = 700;
              style = "Bold";
              size = 12;
            };
          };
        };
      }
    ];

  meta.name = "panel-digitalclock";
}
