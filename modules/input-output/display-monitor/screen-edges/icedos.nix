{ icedosLib, lib, ... }:

{
  options.icedos.desktop.kde.screenEdges =
    let
      inherit (icedosLib)
        mkEnumOption
        mkSubmoduleListOption
        ;

      inherit (lib) head readFile;

      inherit (head (fromTOML (readFile ./screen-edges.toml)).icedos.desktop.kde.screenEdges)
        action
        position
        ;
    in
    mkSubmoduleListOption { default = [ ]; } {
      position =
        mkEnumOption
          {
            path = "icedos.desktop.kde.screenEdges.*.position";
            source = ./screen-edges.toml;
            default = position;
          }
          [
            "top"
            "topRight"
            "right"
            "bottomRight"
            "bottom"
            "bottomLeft"
            "left"
            "topLeft"
          ];

      action =
        mkEnumOption
          {
            path = "icedos.desktop.kde.screenEdges.*.action";
            source = ./screen-edges.toml;
            default = action;
          }
          [
            "none"
            "peekAtDesktop"
            "lockScreen"
            "showKRunner"
            "activityManager"
            "applicationLauncher"
            "presentWindowsAllDesktops"
            "presentWindowsCurrentDesktop"
            "presentWindowsCurrentApplication"
            "overview"
            "grid"
            "toggleWindowSwitching"
            "toggleAlternativeWindowSwitching"
          ];
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        {
          config,
          lib,
          ...
        }:

        let
          inherit (config.icedos.desktop.kde) screenEdges;

          inherit (lib)
            attrNames
            concatMapStringsSep
            filter
            foldl'
            listToAttrs
            mkIf
            optional
            optionalAttrs
            ;

          # KWin ElectricBorder enum value per position (9 = disabled/none).
          edgeNumber = {
            top = 0;
            topRight = 1;
            right = 2;
            bottomRight = 3;
            bottom = 4;
            bottomLeft = 5;
            left = 6;
            topLeft = 7;
          };

          # [ElectricBorders] key name per position.
          electricKey = {
            top = "Top";
            topRight = "TopRight";
            right = "Right";
            bottomRight = "BottomRight";
            bottom = "Bottom";
            bottomLeft = "BottomLeft";
            left = "Left";
            topLeft = "TopLeft";
          };

          # Built-in callback actions -> [ElectricBorders] string value.
          callbackValue = {
            none = "None";
            peekAtDesktop = "ShowDesktop";
            lockScreen = "LockScreen";
            showKRunner = "KRunner";
            activityManager = "ActivityManager";
            applicationLauncher = "ApplicationLauncher";
          };

          # Effect/TabBox actions -> kwinrc group + key. Value is an IntList of
          # edge numbers (verified against each effect plugin's own kcfg).
          effectBorder = {
            presentWindowsAllDesktops = {
              group = "Effect-windowview";
              key = "BorderActivateAll";
            };

            presentWindowsCurrentDesktop = {
              group = "Effect-windowview";
              key = "BorderActivate";
            };

            presentWindowsCurrentApplication = {
              group = "Effect-windowview";
              key = "BorderActivateClass";
            };

            overview = {
              group = "Effect-overview";
              key = "BorderActivate";
            };

            grid = {
              group = "Effect-overview";
              key = "GridBorderActivate";
            };

            toggleWindowSwitching = {
              group = "TabBox";
              key = "BorderActivate";
            };

            toggleAlternativeWindowSwitching = {
              group = "TabBox";
              key = "BorderAlternativeActivate";
            };
          };

          isCallback = action: callbackValue ? ${action};

          # [ElectricBorders]: callback string per listed position; "None" when an
          # effect claims the edge (clears any electric callback there).
          electricBorders = listToAttrs (
            map (edge: {
              name = electricKey.${edge.position};
              value = if isCallback edge.action then callbackValue.${edge.action} else "None";
            }) screenEdges
          );

          # Comma-joined edge numbers of the positions bound to an effect action
          # (IntList). Empty string => no position selected this effect.
          assignedEdges =
            action:
            concatMapStringsSep "," (edge: toString edgeNumber.${edge.position}) (
              filter (edge: edge.action == action) screenEdges
            );

          topLeftClaimed = filter (edge: edge.position == "topLeft") screenEdges != [ ];
          overviewAssigned = assignedEdges "overview" != "";

          # One { group; key; value } per emitted effect border.
          effectEntries =
            (foldl' (
              acc: action:
              let
                edges = assignedEdges action;
              in
              acc ++ optional (edges != "") (effectBorder.${action} // { value = edges; })
            ) [ ] (attrNames effectBorder))
            # topLeft taken by something other than Overview -> disable the KDE
            # default Overview border ([Effect-overview] BorderActivate=7).
            ++ optional (topLeftClaimed && !overviewAssigned) {
              group = "Effect-overview";
              key = "BorderActivate";
              value = "9";
            };

          # Merge effect entries into { <group> = { <key> = value; }; }.
          effectGroups = foldl' (
            acc: entry:
            acc
            // {
              ${entry.group} = (acc.${entry.group} or { }) // {
                ${entry.key} = entry.value;
              };
            }
          ) { } effectEntries;

          kwinrc =
            (optionalAttrs (electricBorders != { }) { ElectricBorders = electricBorders; }) // effectGroups;
        in
        {
          home-manager.sharedModules = [
            (mkIf (screenEdges != [ ]) {
              programs.plasma.configFile.kwinrc = kwinrc;
            })
          ];
        }
      )
    ];

  meta.name = "screen-edges";
}
