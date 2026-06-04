{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      (
        { config, ... }:
        let
          inherit (config.icedos.desktop) clock stylix;
        in
        {
          icedos.desktop.kde.panel.applets."org.kde.plasma.digitalclock" = {
            digitalClock = {
              date.enable = clock.date;

              time = {
                showSeconds = if clock.seconds then "always" else "never";
                format = if clock.hourFormat24 then "24h" else "12h";
              };

              font = {
                family = stylix.fonts.monospace.name;
                bold = true;
                weight = 700;
                style = "Bold";
                size = 12;
              };
            };
          };
        }
      )
    ];

  meta.name = "panel-digitalclock";
}
