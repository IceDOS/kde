"""Displays through PowerDevil, or over DDC/CI (external) and sysfs / logind (internal panels like eDP)."""
import json
import re
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path

BRIGHTNESS = "10"
POWER = "d6"
ASLEEP = (2, 3, 4, 5)  # D6 sl: standby, suspend, off, off (write-only)
# A display that does not answer is left alone rather than reported as broken.
DDC_ERROR = (subprocess.SubprocessError, RuntimeError)
TYPE_PREF = {"raw": 0, "platform": 1, "firmware": 2}
KDE = "org.kde.ScreenBrightness"
KDE_PATH = "/org/kde/ScreenBrightness"
SUPPRESS_OSD = "1"
REPROBE_EVERY = 600  # seconds between KWin DDC re-probes of one monitor


@dataclass(frozen=True)
class Display:
    bus: str  # i2c bus number (ddcutil --bus), "backlight:<name>" or "kde:<PowerDevil display>"
    label: str  # monitor model or connector name (e.g. eDP-1), matches config and widget
    brightness: int
    max: int
    power: int = 1

    @property
    def pct(self) -> float:
        return 100 * self.brightness / self.max if self.max else 0.0

    @property
    def awake(self) -> bool:
        return self.power not in ASLEEP


def _ddcutil(*args: str) -> str:
    p = subprocess.run(["ddcutil", *args], capture_output=True, text=True, timeout=15)
    if p.returncode:
        raise RuntimeError((p.stderr or p.stdout).strip() or f"ddcutil {' '.join(args)} exited {p.returncode}")
    return p.stdout


def _busctl(*args: str, scope: str = "--system") -> str:
    p = subprocess.run(["busctl", scope, *args], capture_output=True, text=True, timeout=5)
    if p.returncode:
        raise RuntimeError((p.stderr or p.stdout).strip() or f"busctl {' '.join(args)} exited {p.returncode}")
    return p.stdout


def _kscreen(*args: str) -> str:
    p = subprocess.run(["kscreen-doctor", *args], capture_output=True, text=True, timeout=10)
    if p.returncode:
        raise RuntimeError((p.stderr or p.stdout).strip() or f"kscreen-doctor {' '.join(args)} exited {p.returncode}")
    return p.stdout


def _read_int(path: Path) -> int | None:
    try:
        return int(path.read_text().strip())
    except (OSError, ValueError):
        return None


def _backlight_devices(root: Path) -> list[tuple[str, Path, int, int]]:
    """Returns list of (name, path, cur_brightness, max_brightness) sorted by driver preference."""
    bl_dir = root / "sys/class/backlight"
    if not bl_dir.is_dir():
        return []
    devs = []
    try:
        for entry in bl_dir.iterdir():
            cur = _read_int(entry / "actual_brightness")
            if cur is None:
                cur = _read_int(entry / "brightness")
            mx = _read_int(entry / "max_brightness")
            if cur is not None and mx is not None and mx > 0:
                t = ""
                try:
                    t = (entry / "type").read_text().strip()
                except OSError:
                    pass
                prio = TYPE_PREF.get(t, 99)
                devs.append((prio, entry.name, entry, cur, mx))
    except OSError:
        return []
    devs.sort(key=lambda x: (x[0], x[1]))
    return [(d[1], d[2], d[3], d[4]) for d in devs]


def _detect_edp(root: Path = Path("/")) -> list[Display]:
    backlights = _backlight_devices(root)
    if not backlights:
        return []

    drm_dir = root / "sys/class/drm"
    connectors = []
    if drm_dir.is_dir():
        try:
            for p in drm_dir.iterdir():
                m = re.match(r"^card\d+-(eDP.*|LVDS.*|DSI.*)", p.name)
                if not m:
                    continue
                try:
                    status = (p / "status").read_text().strip()
                except OSError:
                    status = "connected"
                if status != "connected":
                    continue
                try:
                    dpms = (p / "dpms").read_text().strip()
                except OSError:
                    dpms = "On"
                power = 4 if dpms == "Off" else 1
                connectors.append((m.group(1), p, power))
        except OSError:
            pass

    out = []
    if connectors:
        used_bl: set[str] = set()
        for label, conn_path, power in connectors:
            matched = None
            conn_bl = conn_path / "backlight"
            if conn_bl.is_dir():
                try:
                    for sub in conn_bl.iterdir():
                        for name, _path, cur, mx in backlights:
                            if name == sub.name:
                                matched = (name, cur, mx)
                                break
                        if matched:
                            break
                except OSError:
                    pass
            if not matched:
                available = [b for b in backlights if b[0] not in used_bl]
                b = available[0] if available else backlights[0]
                matched = (b[0], b[2], b[3])

            used_bl.add(matched[0])
            out.append(Display(f"backlight:{matched[0]}", label, matched[1], matched[2], power))
    else:
        b_name, _, cur, mx = backlights[0]
        out.append(Display(f"backlight:{b_name}", "eDP-1", cur, mx, 1))

    return out


def _label(model: str) -> str:
    # "AUS:MG248:serial" and "XMI:Mi Monitor:" both drop to the model part.
    parts = [p.strip() for p in model.split(":")]
    return parts[1] if len(parts) > 1 and parts[1] else parts[0]


def _detect(run=_ddcutil) -> list[tuple[str, str, str]]:
    """(bus, label, DRM connector such as DP-1) for each display that answers DDC."""
    blocks, cur = [], {}
    for line in run("detect", "--brief").splitlines():
        s = line.strip()
        if re.match(r"Display\s+\d+|Invalid display", s):
            if cur.get("bus") and not cur.get("invalid"):
                blocks.append(cur)
            # Invalid blocks are phantom buses; without a reset they overwrite the previous display.
            cur = {"invalid": s.startswith("Invalid")}
        elif m := re.match(r"I2C bus:\s*/dev/i2c-(\d+)", s):
            cur["bus"] = m.group(1)
        elif m := re.match(r"DRM connector:\s*card\d+-(\S+)", s):
            cur["connector"] = m.group(1)
        elif s.startswith("Monitor:"):
            cur["model"] = s.split(":", 1)[1]
    if cur.get("bus") and not cur.get("invalid"):
        blocks.append(cur)
    return [(b["bus"], _label(b["model"]), b.get("connector", "")) for b in blocks if b.get("model")]


def _connected_outputs(root: Path) -> frozenset[str]:
    try:
        entries = list((root / "sys/class/drm").iterdir())
    except OSError:
        return frozenset()
    out = set()
    for p in entries:
        m = re.match(r"^card\d+-(.+)", p.name)
        if not m or m.group(1).startswith("Writeback"):
            continue
        try:
            if (p / "status").read_text().strip() == "connected":
                out.add(m.group(1))
        except OSError:
            pass
    return frozenset(out)


def _vcp(bus: str, code: str, run=_ddcutil) -> tuple[int, int]:
    """(current, max); power mode has no max, so it comes back as 0."""
    out = run("--bus", bus, "getvcp", code)
    if m := re.search(r"sl\s*=\s*0x([0-9a-fA-F]+)", out):
        return int(m.group(1), 16), 0
    if m := re.search(r"current value\s*=\s*(\d+),\s*max value\s*=\s*(\d+)", out):
        return int(m.group(1)), int(m.group(2))
    raise RuntimeError(f"ddcutil: unreadable VCP {code}: {out.strip()}")


def _kde_bus(*args: str) -> str:
    return _busctl("--json=short", *args, scope="--user")


def _kde_displays(run_kde) -> list[Display]:
    names = json.loads(run_kde("get-property", KDE, KDE_PATH, KDE, "DisplaysDBusNames"))["data"]
    out = []
    for name in names:
        raw = run_kde("call", KDE, f"{KDE_PATH}/{name}", "org.freedesktop.DBus.Properties", "GetAll", "s", f"{KDE}.Display")
        props = {k: v["data"] for k, v in json.loads(raw)["data"][0].items()}
        out.append(Display(f"kde:{name}", props["Label"], props["Brightness"], props["MaxBrightness"]))
    return out


def _ddc_display(bus: str, label: str, run) -> Display:
    try:
        cur, mx = _vcp(bus, BRIGHTNESS, run)
    except DDC_ERROR:
        return Display(bus, label, 0, 100, 4)  # silent bus: asleep or busy, so leave it alone
    try:
        power = _vcp(bus, POWER, run)[0]
    except DDC_ERROR:
        power = 1  # it just answered brightness, so 0xD6 is simply unsupported
    return Display(bus, label, cur, mx, power)


# ddcutil detect is slow, so it reruns only when the connected outputs or PowerDevil's list change.
_lost: dict = {"key": None, "missing": []}
_reprobed: dict[str, float] = {}


def _lost_by_kde(kde: list[Display], run, sysfs_root: Path, run_kscreen) -> list[Display]:
    """Monitors that answer DDC but that KWin's probe at login missed, so PowerDevil does not list them."""
    outputs = _connected_outputs(sysfs_root)
    labels = frozenset(d.label for d in kde)
    if _lost["key"] != (outputs, labels):
        missing = []
        if len(kde) < len(outputs):
            try:
                missing = [m for m in _detect(run) if m[1] not in labels]
            except DDC_ERROR:
                pass
        _lost.update(key=(outputs, labels), missing=missing)

    out = []
    now = time.monotonic()
    for bus, label, connector in _lost["missing"]:
        # Toggling DDC/CI off and on makes KWin probe again; PowerDevil then lists the monitor.
        if connector and now - _reprobed.get(connector, -REPROBE_EVERY) >= REPROBE_EVERY:
            _reprobed[connector] = now
            try:
                run_kscreen(f"output.{connector}.ddcCi.disallow")
                run_kscreen(f"output.{connector}.ddcCi.allow")
            except (*DDC_ERROR, OSError):
                pass
        out.append(_ddc_display(bus, label, run))
    return out


def list_displays(run=_ddcutil, sysfs_root: Path = Path("/"), run_kde=None, run_kscreen=None) -> list[Display]:
    # PowerDevil restores its own cached level on wake, so writes must go through it when it runs.
    try:
        kde = _kde_displays(run_kde or _kde_bus)
    except (*DDC_ERROR, OSError, ValueError, KeyError, IndexError):
        kde = None
    if kde is not None:
        return kde + _lost_by_kde(kde, run, sysfs_root, run_kscreen or _kscreen)
    return _detect_edp(sysfs_root) + [_ddc_display(bus, label, run) for bus, label, _ in _detect(run)]


def set_brightness(bus: str, raw: int, run=_ddcutil, run_bus=_busctl, run_kde=None) -> None:
    if bus.startswith("kde:"):
        name = bus.split(":", 1)[1]
        (run_kde or _kde_bus)("call", KDE, f"{KDE_PATH}/{name}", f"{KDE}.Display", "SetBrightness", "iu", str(raw), SUPPRESS_OSD)
    elif bus.startswith("backlight:"):
        dev = bus.split(":", 1)[1]
        run_bus(
            "call",
            "org.freedesktop.login1",
            "/org/freedesktop/login1/session/auto",
            "org.freedesktop.login1.Session",
            "SetBrightness",
            "ssu",
            "backlight",
            dev,
            str(raw),
        )
    else:
        run("--bus", bus, "setvcp", BRIGHTNESS, str(raw))
