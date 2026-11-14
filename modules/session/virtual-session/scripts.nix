{
  pkgs,
  lib,
  home,
}:

let
  isolated = home == "isolated";
  homeSubdir = ".local/state/icedos/sunshine-headless/kwin/home";

  homeEnv = root: {
    HOME = root;
    XDG_CONFIG_HOME = "${root}/.config";
    XDG_DATA_HOME = "${root}/.local/share";
    XDG_CACHE_HOME = "${root}/.cache";
    XDG_STATE_HOME = "${root}/.local/state";
  };

  portalKde = pkgs.kdePackages.xdg-desktop-portal-kde;

  # xdg-desktop-portal lowercases the desktop name for this file.
  portalConfig = pkgs.writeTextDir "xdg-desktop-portal/kde-portals.conf" ''
    [preferred]
    default=kde
  '';

  socket = "sunshine-headless-kwin";
  unit = "sunshine-headless-kwin.service";
  portalDir = "${portalKde}/share/xdg-desktop-portal/portals";
  relayUnit = "sunshine-headless-kwin-wallet-relay.service";

  relayPkg = pkgs.writers.writePython3Bin "kwin-wallet-relay" {
    libraries = [ pkgs.python3Packages.jeepney ];
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./kwin-wallet-relay.py);

  serviceFile =
    name: exec:
    pkgs.writeTextDir "share/dbus-1/services/${name}.service" ''
      [D-BUS Service]
      Name=${name}
      Exec=${exec}
    '';

  # Holds the kde-authorized grant, whose app id "" would match every unsandboxed app on the real store.
  permissionStore = pkgs.writeShellScript "kwin-permission-store" ''
    export XDG_DATA_HOME="$XDG_RUNTIME_DIR/sunshine-portal/kwin/data"
    exec ${pkgs.xdg-desktop-portal}/libexec/xdg-permission-store
  '';

  # A bus-activated copy of these would run without the right env, or open the real wallet a second time.
  deniedServices = [
    "org.freedesktop.portal.Desktop"
  ]
  ++ lib.optionals (!isolated) [
    "org.freedesktop.impl.portal.desktop.kwallet"
    "org.freedesktop.secrets"
    "org.kde.ksecretd"
    "org.kde.kwalletd"
    "org.kde.kwalletd5"
    "org.kde.kwalletd6"
    "org.kde.secretservicecompat"
  ];

  serviceOverrides = pkgs.symlinkJoin {
    name = "sunshine-headless-kwin-service-overrides";
    paths = [
      (serviceFile "org.freedesktop.impl.portal.PermissionStore" permissionStore)
    ]
    ++ map (name: serviceFile name "${pkgs.coreutils}/bin/false") deniedServices;
  };

  kwinConfigArgs =
    if isolated then
      lib.concatStringsSep " " (
        lib.mapAttrsToList (name: value: ''--setenv=${name}="${value}"'') (homeEnv "$state/home")
      )
    else
      # KConfig falls back to the real files for reads, like effect configs, and still writes to $state.
      ''--setenv=XDG_CONFIG_HOME="$state/config" --setenv=XDG_CONFIG_DIRS="$HOME/.config:''${XDG_CONFIG_DIRS:-/etc/xdg}"'';

  inputBridgePkg =
    pkgs.runCommandCC "kwin-input-bridge"
      {
        nativeBuildInputs = [ pkgs.pkg-config ];
        buildInputs = [
          pkgs.libei
          pkgs.systemd
        ];
      }
      ''
        mkdir -p $out/bin
        $CC -O2 -Wall -Wextra -Wno-unused-parameter ${./kwin-input-bridge.c} \
          $(pkg-config --cflags --libs libei-1.0 libsystemd) -o $out/bin/kwin-input-bridge
      '';
in
{
  waylandDisplay = socket;
  inputBridge = true;

  packages = [
    pkgs.glib
    pkgs.kdePackages.kwin
    pkgs.procps
  ];

  portal = {
    # Started by kwin_start: portal-kde exits if its Wayland socket is not up yet.
    autoStart = false;

    serviceDirs = [
      "${serviceOverrides}/share/dbus-1/services"
      "${pkgs.xdg-desktop-portal}/share/dbus-1/services"
      "${portalKde}/share/dbus-1/services"
    ];

    busEnvironment = {
      WAYLAND_DISPLAY = socket;
      XDG_CURRENT_DESKTOP = "KDE";
      XDG_SESSION_TYPE = "wayland";
      QT_QPA_PLATFORM = "wayland";
      XDG_DATA_DIRS = "/run/current-system/sw/share";
    }
    // lib.optionalAttrs isolated (homeEnv "%h/${homeSubdir}");

    environment = {
      WAYLAND_DISPLAY = socket;
      XDG_CURRENT_DESKTOP = "KDE";
      XDG_CONFIG_HOME = "${portalConfig}";
      XDG_DATA_DIRS = "/run/current-system/sw/share";
      XDG_DATA_HOME = "%t/sunshine-portal/kwin/data";
      NIX_XDG_DESKTOP_PORTAL_DIR = portalDir;
      XDG_DESKTOP_PORTAL_DIR = portalDir;
    };
  };

  helpers = ''
    kwin_bus="unix:path=$rt/sunshine-portal/kwin/bus"
    kwin_params="$rt/sunshine-headless-kwin-params"
    kwin_marker="$rt/sunshine-headless-kwin-stopping"

    kwin_up() {
      [ -S "$rt/${socket}" ] && systemctl --user is-active --quiet ${unit}
    }

    # Other KWin apps would lose their compositor on a restart.
    kwin_apps_running() {
      local f name
      for f in "$rt"/sunshine-headless-app-*.active; do
        [ -e "$f" ] || continue
        name="$(cat "$f" 2>/dev/null || true)"
        [ -n "$name" ] && [ "$name" != "$app_name" ] || continue
        ( app_setup "$name" >/dev/null 2>&1 && [ "$app_compositor" = kwin ] ) && return 0
      done
      return 1
    }

    kwin_stop() {
      kwin_bridge_stop
      : >"$kwin_marker"
      systemctl --user stop --quiet ${unit} 2>/dev/null || true
      rm -f "$kwin_marker" "$kwin_params"
      systemctl --user reset-failed ${unit} 2>/dev/null || true
      systemctl --user stop --quiet sunshine-portal-kwin.service 2>/dev/null || true
      systemctl --user stop --quiet ${relayUnit} 2>/dev/null || true
    }

    # KWin picks free X displays at startup and writes its pid to their lock files; the lowest is the real one.
    kwin_x_display() {
      local pid f n best=""
      pid="$(systemctl --user show -p MainPID --value ${unit} 2>/dev/null)"
      if [ -z "$pid" ] || [ "$pid" = 0 ]; then
        return 0
      fi
      for f in /tmp/.X*-lock; do
        if [ "$(tr -d ' ' <"$f" 2>/dev/null)" != "$pid" ]; then
          continue
        fi
        n="''${f#/tmp/.X}"
        n="''${n%-lock}"
        if [ -z "$best" ] || [ "$n" -lt "$best" ]; then
          best="$n"
        fi
      done
      if [ -n "$best" ]; then
        printf ':%s' "$best"
      fi
    }

    # Apps start after this returns, so the private bus never activates its own wallet.
    kwin_relay_start() {
      local i
      systemctl --user stop --quiet ${relayUnit} 2>/dev/null || true
      systemctl --user reset-failed ${relayUnit} 2>/dev/null || true
      systemd-run --user --collect \
        --unit=${relayUnit} \
        --property=Restart=on-failure \
        --property=RestartSec=1s \
        --property=BindsTo=sunshine-portal-bus-kwin.service \
        --property=After=sunshine-portal-bus-kwin.service \
        --setenv=DBUS_SESSION_BUS_ADDRESS="unix:path=$rt/bus" \
        -- ${relayPkg}/bin/kwin-wallet-relay "$kwin_bus"
      for i in $(seq 1 50); do
        if busctl --address="$kwin_bus" call org.freedesktop.DBus / org.freedesktop.DBus \
          NameHasOwner s org.kde.kwalletd6 2>/dev/null | grep -q true; then
          return 0
        fi
        sleep 0.1
      done
      echo "sunshine-headless: wallet relay not ready within 5s (see: journalctl --user -u ${relayUnit})" >&2
      exit 1
    }

    # A child of the prep command, so it keeps the daemon's `input` group.
    kwin_bridge_start() {
      kwin_bridge_stop
      env DBUS_SESSION_BUS_ADDRESS="$kwin_bus" \
        setpriv --inh-caps=-all --ambient-caps=-all -- \
        setsid -f ${inputBridgePkg}/bin/kwin-input-bridge \
        >"$rt/sunshine-headless-kwin-input.log" 2>&1
    }

    kwin_bridge_stop() {
      pkill -f '/bin/kwin-input-bridge$' 2>/dev/null || true
    }

    # Separate process tree from the desktop's KWin, with its config kept out of ~/.config.
    kwin_start() {
      local w="$1" h="$2" i
      local state="$HOME/.local/state/icedos/sunshine-headless/kwin"
      local legacy_state="$HOME/.local/state/sunshine-headless/kwin" # legacy path pre-2026-11
      if [ ! -e "$state" ] && [ -d "$legacy_state" ]; then
        mkdir -p "$(dirname "$state")"
        mv "$legacy_state" "$state"
      elif [ -d "$state" ] && [ -d "$legacy_state" ]; then
        echo "sunshine-headless: legacy state dir $legacy_state ignored" >&2
      fi
      ${
        if isolated then
          ''mkdir -p "$state/home/.config" "$state/home/.local/share" "$state/home/.local/state" "$state/home/.cache"''
        else
          ''
            mkdir -p "$state/config"
            # A copy, because KWin writes its virtual output into the config it runs from.
            local f
            for f in kwinrc kdeglobals kwinrulesrc breezerc; do
              if [ -f "$HOME/.config/$f" ]; then
                install -m 600 "$HOME/.config/$f" "$state/config/$f"
              fi
            done
            kwin_relay_start
          ''
      }
      systemctl --user reset-failed ${unit} 2>/dev/null || true
      systemd-run --user --collect \
        --unit=${unit} \
        --property=Type=simple \
        --property=BindsTo=sunshine-portal-bus-kwin.service \
        --property=After=sunshine-portal-bus-kwin.service \
        --property=Restart=on-failure \
        --property="ExecStopPost=$self drain kwin" \
        --property="UnsetEnvironment=WAYLAND_DISPLAY DISPLAY QT_QPA_PLATFORM KDE_FULL_SESSION KDE_SESSION_VERSION" \
        --setenv=DBUS_SESSION_BUS_ADDRESS="$kwin_bus" \
        ${kwinConfigArgs} \
        --setenv=XDG_CURRENT_DESKTOP=KDE \
        --setenv=XDG_SESSION_TYPE=wayland \
        --setenv=KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 \
        --setenv=KWIN_SCREENSHOT_NO_PERMISSION_CHECKS=1 \
        -- ${pkgs.kdePackages.kwin}/bin/kwin_wayland \
          --virtual --xwayland --no-lockscreen --no-global-shortcuts \
          --width "$w" --height "$h" \
          --socket ${socket}
      for i in $(seq 1 300); do
        if [ -S "$rt/${socket}" ] && busctl --address="$kwin_bus" list --no-pager 2>/dev/null | grep -q '^org\.kde\.KWin '; then
          break
        fi
        sleep 0.1
      done
      if ! [ -S "$rt/${socket}" ] || [ "$i" -ge 300 ]; then
        echo "sunshine-headless: KWin not ready within 30s (see: journalctl --user -u ${unit})" >&2
        exit 1
      fi
      for i in $(seq 1 30); do
        if [ -n "$(kwin_x_display)" ]; then
          break
        fi
        sleep 0.1
      done
      # The helper path changes with every rebuild of this script, so ensure can spot an old KWin.
      printf '%s %s %s' "$w" "$h" "$self" >"$kwin_params"
      systemctl --user restart sunshine-portal-kwin.service
      # Without this entry portal-kde shows a dialog nobody can answer.
      gdbus call --address "$kwin_bus" \
        --dest org.freedesktop.impl.portal.PermissionStore \
        --object-path /org/freedesktop/impl/portal/PermissionStore \
        --method org.freedesktop.impl.portal.PermissionStore.SetPermission \
        kde-authorized true remote-desktop "" "['yes']" >/dev/null
    }
  '';

  hooks = {
    ensure = ''
      local w="''${1:-1920}" h="''${2:-1080}" saved
      saved="$(cat "$kwin_params" 2>/dev/null || true)"
      if kwin_up; then
        if [ "$saved" != "$w $h $self" ]; then
          if streaming_active kwin; then
            echo "start: keeping KWin (stream active); app joins at the current geometry and build" >&2
          elif [ "''${saved##* }" != "$self" ] && kwin_apps_running; then
            echo "start: keeping KWin from an older build while another KWin app runs" >&2
          else
            kwin_stop
            kwin_start "$w" "$h"
          fi
        fi
      else
        kwin_start "$w" "$h"
      fi
      kwin_bridge_start
    '';

    release = ''
      kwin_bridge_stop
    '';

    appEnv = ''
      local x_display
      x_display="$(kwin_x_display)"
      if [ -n "$x_display" ]; then
        compositor_env+=("DISPLAY=$x_display")
      else
        app_unset_env+=(DISPLAY)
      fi
      compositor_env+=(
        "WAYLAND_DISPLAY=${socket}"
        "DBUS_SESSION_BUS_ADDRESS=$kwin_bus"
        "QT_QPA_PLATFORM=wayland"
        "XDG_SESSION_TYPE=wayland"
        "XDG_CURRENT_DESKTOP=KDE"
        "KDE_FULL_SESSION=true"
        "KDE_SESSION_VERSION=6"
        # The shared app PATH omits this for Steam's FHS, where /etc is empty; KWin apps run outside it.
        "PATH=$app_path:/etc/profiles/per-user/$(id -un)/bin"
        ${lib.concatStringsSep "\n        " (
          lib.optionals isolated (
            lib.mapAttrsToList (name: value: ''"${name}=${value}"'') (homeEnv "$HOME/${homeSubdir}")
          )
        )}
      )
    '';

    probe = ''
      kwin_up || kwin_start 1280 720
    '';

    recycle = ''
      local hb="$rt/sunshine-headless-stream-hb-kwin" now hb_at idle f recycle_idle=""
      if streaming_active kwin; then
        touch "$hb" 2>/dev/null || true
        return 0
      fi
      kwin_up || return 0
      # The default compositor must stay up for Sunshine's startup probe.
      [ "$default_compositor" != kwin ] || return 0
      for f in "$rt"/sunshine-headless-app-*.active; do
        [ -e "$f" ] || continue
        app_setup "$(cat "$f" 2>/dev/null || true)" 2>/dev/null || continue
        [ "$app_compositor" = kwin ] || continue
        recycle_idle="$app_idle_timeout"
        break
      done
      idle="''${recycle_idle:-$session_idle_timeout}"
      now="$(date +%s)"
      hb_at="$(stat -c %Y "$hb" 2>/dev/null || echo 0)"
      if [ "$idle" -gt 0 ] && [ $(( now - hb_at )) -ge "$idle" ]; then
        recycle_stop_sessions kwin
        kwin_stop
        retarget_portal_away_from kwin
      fi
    '';
  };
}
