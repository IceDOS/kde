{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      (
        { config, lib, ... }:
        let
          inherit (config.icedos.desktop) clock stylix;
          inherit (lib) optionals;
        in
        {
          icedos.system.tips.list = [
            "Click the clock in your panel to open the calendar."
          ]
          ++ optionals clock.seconds [
            "Your panel clock counts seconds; set seconds to false under [icedos.desktop.clock] for a calmer one."
          ];

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
