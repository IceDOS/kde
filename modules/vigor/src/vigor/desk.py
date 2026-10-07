"""Session-side controls for the widget: power profile, device batteries, inhibitors and holds."""
import json
import os
import signal
import subprocess
import time
from pathlib import Path

from . import bus, tune

SYSTEM, SESSION = "SYSTEM", "SESSION"
# Set by the Nix wrapper; pkexec and systemd-run need the absolute path the polkit rule names.
BIN = os.environ.get("VIGOR_BIN", "")
# Off when icedos.desktop.kde.vigor.tune is false: no polkit rule, so the slider stays on the daemon.
TUNE = os.environ.get("VIGOR_TUNE", "1") == "1"
PKEXEC = "/run/wrappers/bin/pkexec"
HOLD_STATE = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "vigor" / "holds.json"
WHO = "vigor"

_PPD = [
    ("org.freedesktop.UPower.PowerProfiles", "/org/freedesktop/UPower/PowerProfiles", "org.freedesktop.UPower.PowerProfiles"),
    ("net.hadess.PowerProfiles", "/net/hadess/PowerProfiles", "net.hadess.PowerProfiles"),
]
_LOGIN = ("org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager")
_AGENT = ("org.kde.Solid.PowerManagement", "/org/kde/Solid/PowerManagement/PolicyAgent",
          "org.kde.Solid.PowerManagement.PolicyAgent")
_UPOWER = ("org.freedesktop.UPower", "/org/freedesktop/UPower", "org.freedesktop.UPower")
_SYSTEMD = ("org.freedesktop.systemd1", "/org/freedesktop/systemd1", "org.freedesktop.systemd1.Manager")

# kind: (service, path, interface, method, signature, args)
HOLDS = {
    "idle": ("org.freedesktop.ScreenSaver", "/org/freedesktop/ScreenSaver", "org.freedesktop.ScreenSaver",
             "Inhibit", "ss", (WHO, "Screen kept awake from the panel")),
    "sleep": ("org.freedesktop.PowerManagement", "/org/freedesktop/PowerManagement/Inhibit",
              "org.freedesktop.PowerManagement.Inhibit", "Inhibit", "ss", (WHO, "Sleep blocked from the panel")),
    "dnd": ("org.freedesktop.Notifications", "/org/freedesktop/Notifications", "org.freedesktop.Notifications",
            "Inhibit", "ssa{sv}", (WHO, "Do not disturb from the panel", {})),
    "nightlight": ("org.kde.KWin", "/org/kde/KWin/NightLight", "org.kde.KWin.NightLight", "inhibit", "", ()),
}

DEVICE_KINDS = {
    1: "line-power", 2: "battery", 3: "ups", 4: "monitor", 5: "mouse", 6: "keyboard", 7: "pda", 8: "phone",
    9: "media-player", 10: "tablet", 11: "computer", 12: "gaming-input", 13: "pen", 14: "touchpad",
    15: "modem", 16: "network", 17: "headset", 18: "speakers", 19: "headphones", 20: "video",
    21: "other-audio", 22: "remote-control", 23: "printer", 24: "scanner", 25: "camera", 26: "wearable",
    27: "toy", 28: "bluetooth",
}
STATES = {1: "charging", 2: "discharging", 3: "empty", 4: "full", 5: "pending-charge", 6: "pending-discharge"}
# UPower's coarse BatteryLevel; 1 (none) means Percentage is exact.
LEVELS = {3: "low", 4: "critical", 6: "normal", 7: "high", 8: "full"}


def _read(p: Path) -> str | None:
    try:
        return p.read_text().strip()
    except OSError:
        return None


def ppd() -> dict | None:
    for svc in _PPD:
        p = bus.props(SYSTEM, *svc)
        if p:
            profiles = p.get("Profiles", [])
            # A placeholder driver means the daemon only records the choice and changes no hardware.
            managed = any(prof.get(k) not in (None, "", "placeholder")
                          for prof in profiles for k in ("CpuDriver", "PlatformDriver", "Driver"))
            return {
                "service": svc,
                "active": p.get("ActiveProfile", ""),
                "profiles": [prof.get("Profile", "") for prof in profiles],
                "managed": managed,
                "degraded": p.get("PerformanceDegraded", ""),
                "holds": [{"app": h.get("ApplicationId", ""), "profile": h.get("Profile", ""),
                           "reason": h.get("Reason", "")} for h in p.get("ActiveProfileHolds", [])],
            }
    return None


def profile_state(root: Path, daemon: dict | None) -> dict | None:
    out = {"holds": daemon["holds"] if daemon else [], "degraded": daemon["degraded"] if daemon else ""}
    if daemon and daemon["managed"]:
        return {**out, "source": "ppd", "active": daemon["active"],
                "available": [p for p in tune.PROFILES if p in daemon["profiles"]]}
    if TUNE and BIN and tune.policies(root):
        return {**out, "source": "cpufreq", "active": tune.current(root), "available": list(tune.PROFILES)}
    if daemon:
        return {**out, "source": "ppd", "active": daemon["active"],
                "available": [p for p in tune.PROFILES if p in daemon["profiles"]]}
    return None


def cpu(root: Path) -> dict:
    pol = tune.policies(root)
    cur = [int(v) for p in pol if (v := _read(p / "scaling_cur_freq")) and v.isdigit()]
    top = _read(pol[0] / "cpuinfo_max_freq") if pol else None
    return {
        "governor": _read(pol[0] / "scaling_governor") if pol else None,
        "driver": _read(pol[0] / "scaling_driver") if pol else None,
        "boost": tune.read_boost(root),
        "mhz": round(sum(cur) / len(cur) / 1000) if cur else None,
        "peak_mhz": round(max(cur) / 1000) if cur else None,
        "max_mhz": round(int(top) / 1000) if top and top.isdigit() else None,
    }


def sensors(root: Path) -> dict:
    temps, fans = [], []
    for hw in sorted((root / "sys/class/hwmon").glob("hwmon*"), key=lambda p: int(p.name[5:] or 0)):
        name = _read(hw / "name") or hw.name
        t = _read(hw / "temp1_input")
        if t and t.lstrip("-").isdigit():
            temps.append({"chip": name, "label": _read(hw / "temp1_label") or "", "c": int(t) / 1000})
        for f in sorted(hw.glob("fan[0-9]*_input")):
            rpm = _read(f)
            if rpm and rpm.isdigit() and int(rpm) > 0:
                label = _read(f.with_name(f.name.replace("_input", "_label")))
                fans.append({"chip": name, "label": label or f.name.split("_")[0], "rpm": int(rpm)})
    return {"temps": temps, "fans": fans}


def device(p: dict) -> dict:
    level = LEVELS.get(p.get("BatteryLevel", 1))
    return {
        "kind": DEVICE_KINDS.get(p.get("Type", 0), "unknown"),
        "model": p.get("Model", ""),
        "vendor": p.get("Vendor", ""),
        "percent": None if level else p.get("Percentage"),
        "level": level,
        "state": STATES.get(p.get("State", 0), "unknown"),
        "icon": p.get("IconName", ""),
        "rate_w": p.get("EnergyRate") or None,
        "time_to_empty": p.get("TimeToEmpty") or None,
        "time_to_full": p.get("TimeToFull") or None,
        "power_supply": bool(p.get("PowerSupply")),
    }


def batteries() -> tuple[list[dict], bool]:
    paths = bus.call(SYSTEM, _UPOWER[0], _UPOWER[1], _UPOWER[2], "EnumerateDevices") or []
    out = []
    for path in paths:
        p = bus.props(SYSTEM, _UPOWER[0], path, "org.freedesktop.UPower.Device")
        if p.get("Type") in (None, 0, 1) or not p.get("IsPresent", True):
            continue
        out.append(device(p))
    on_battery = bool(bus.prop(SYSTEM, *_UPOWER, "OnBattery"))
    # The machine's own battery first, then peripherals by charge, lowest first.
    out.sort(key=lambda d: (not d["power_supply"], d["percent"] if d["percent"] is not None else 101))
    return out, on_battery


def merge_inhibitors(logind: list, requested: list, active: list) -> list[dict]:
    out, seen = [], set()
    for what, who, why, mode, uid, pid in logind:
        seen.add((who, why))
        out.append({"what": what, "who": who, "why": why, "mode": mode, "pid": pid,
                    "source": "logind", "allowed": True, "ours": who == WHO})
    live = {(w, who, why) for w, who, why, *_ in active}
    for what, who, why, mode, *_ in requested:
        if (who, why) in seen:
            continue
        out.append({"what": what, "who": who, "why": why, "mode": mode, "pid": None,
                    "source": "plasma", "allowed": (what, who, why) in live, "ours": who == WHO})
    out.sort(key=lambda i: (i["mode"] != "block", i["source"] != "plasma", i["who"].lower()))
    return out


def inhibitors() -> list[dict]:
    logind = bus.call(SYSTEM, *_LOGIN, "ListInhibitors") or []
    requested = bus.prop(SESSION, *_AGENT, "RequestedInhibitions") or []
    active = bus.prop(SESSION, *_AGENT, "ActiveInhibitions") or []
    return merge_inhibitors(logind, requested, active)


def _hold_unit(kind: str) -> str:
    return f"vigor-hold-{kind}.service"


def _load_until() -> dict:
    try:
        return json.loads(HOLD_STATE.read_text())
    except (OSError, ValueError):
        return {}


def holds(now: float) -> dict:
    units = bus.call(SESSION, *_SYSTEMD, "ListUnitsByPatterns", "asas",
                     (["active", "activating"], ["vigor-hold-*.service"])) or []
    live = {u[0] for u in units}
    until = _load_until()
    out = {}
    for kind in HOLDS:
        on = _hold_unit(kind) in live
        t = until.get(kind)
        out[kind] = {"on": on, "until": t if on and t and t > now else None}
    return out


def start_hold(kind: str, minutes: int) -> int:
    if kind not in HOLDS or not BIN:
        return 2
    unit = _hold_unit(kind)
    subprocess.run(["systemctl", "--user", "stop", unit], capture_output=True)
    cmd = ["systemd-run", "--user", "--quiet", "--collect", f"--unit={unit}",
           f"--description=vigor: {kind} hold"]
    if minutes > 0:
        cmd.append(f"--property=RuntimeMaxSec={minutes * 60}")
    r = subprocess.run(cmd + [BIN, "hold", kind], capture_output=True)
    until = _load_until()
    until[kind] = time.time() + minutes * 60 if minutes > 0 else None
    HOLD_STATE.parent.mkdir(parents=True, exist_ok=True)
    HOLD_STATE.write_text(json.dumps(until))
    return r.returncode


def stop_hold(kind: str) -> int:
    if kind not in HOLDS:
        return 2
    return subprocess.run(["systemctl", "--user", "stop", _hold_unit(kind)], capture_output=True).returncode


def hold(kind: str) -> int:
    """Hold one inhibition for as long as this process lives; the peer drops it when the bus connection closes."""
    if kind not in HOLDS:
        return 2
    service, path, iface, method, sig, args = HOLDS[kind]
    if bus.call(SESSION, service, path, iface, method, sig, args) is None:
        return 1
    signal.signal(signal.SIGTERM, lambda *_: os._exit(0))
    while True:
        signal.pause()


def set_profile(root: Path, name: str) -> int:
    if name not in tune.PROFILES:
        return 2
    daemon = ppd()
    state = profile_state(root, daemon)
    if state is None:
        return 1
    rc = 0
    if state["source"] == "cpufreq":
        rc = subprocess.run([PKEXEC, BIN, "tune", "apply", name], capture_output=True).returncode
    # Mirror into the daemon too, so Plasma's battery applet and apps reading it agree.
    if daemon and name in daemon["profiles"]:
        if not bus.set_prop(SYSTEM, *daemon["service"], "ActiveProfile", "s", name) and state["source"] == "ppd":
            rc = 1
    return rc


def allow(who: str, why: str, allowed: bool) -> int:
    r = bus.call(SESSION, *_AGENT, "SetInhibitionAllowed", "ssb", (who, why, allowed))
    return 0 if r is not None else 1


def firmware_reboot() -> int:
    return subprocess.run(["systemctl", "reboot", "--firmware-setup"], capture_output=True).returncode


def status(root: Path) -> dict:
    now = time.time()
    devices, on_battery = batteries()
    up = _read(root / "proc/uptime")
    return {
        "ts": now,
        "profile": profile_state(root, ppd()),
        "cpu": cpu(root),
        "sensors": sensors(root),
        "devices": devices,
        "on_battery": on_battery,
        "inhibitors": inhibitors(),
        "holds": holds(now),
        "can_firmware": bus.call(SYSTEM, *_LOGIN, "CanRebootToFirmwareSetup") == "yes",
        "uptime": float(up.split()[0]) if up else None,
    }
