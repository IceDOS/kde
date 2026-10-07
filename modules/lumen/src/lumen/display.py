"""Displays over DDC/CI (external) and sysfs / logind (internal panels like eDP)."""
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path

BRIGHTNESS = "10"
POWER = "d6"
ASLEEP = (2, 3, 4, 5)  # D6 sl: standby, suspend, off, off (write-only)
# A display that does not answer is left alone rather than reported as broken.
DDC_ERROR = (subprocess.SubprocessError, RuntimeError)
TYPE_PREF = {"raw": 0, "platform": 1, "firmware": 2}


@dataclass(frozen=True)
class Display:
    bus: str  # i2c bus number (ddcutil --bus) or "backlight:<name>"
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


def _busctl(*args: str) -> str:
    p = subprocess.run(["busctl", "--system", *args], capture_output=True, text=True, timeout=5)
    if p.returncode:
        raise RuntimeError((p.stderr or p.stdout).strip() or f"busctl {' '.join(args)} exited {p.returncode}")
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


def _detect(run=_ddcutil) -> list[tuple[str, str]]:
    blocks, cur = [], {}
    for line in run("detect", "--brief").splitlines():
        s = line.strip()
        if re.match(r"Display\s+\d+", s):
            if cur.get("bus"):
                blocks.append(cur)
            cur = {}
        elif m := re.match(r"I2C bus:\s*/dev/i2c-(\d+)", s):
            cur["bus"] = m.group(1)
        elif s.startswith("Monitor:"):
            cur["model"] = s.split(":", 1)[1]
    if cur.get("bus"):
        blocks.append(cur)
    return [(b["bus"], _label(b["model"])) for b in blocks if b.get("model")]


def _vcp(bus: str, code: str, run=_ddcutil) -> tuple[int, int]:
    """(current, max); power mode has no max, so it comes back as 0."""
    out = run("--bus", bus, "getvcp", code)
    if m := re.search(r"sl\s*=\s*0x([0-9a-fA-F]+)", out):
        return int(m.group(1), 16), 0
    if m := re.search(r"current value\s*=\s*(\d+),\s*max value\s*=\s*(\d+)", out):
        return int(m.group(1)), int(m.group(2))
    raise RuntimeError(f"ddcutil: unreadable VCP {code}: {out.strip()}")


def list_displays(run=_ddcutil, sysfs_root: Path = Path("/")) -> list[Display]:
    out = _detect_edp(sysfs_root)
    for bus, label in _detect(run):
        try:
            cur, mx = _vcp(bus, BRIGHTNESS, run)
        except DDC_ERROR:
            out.append(Display(bus, label, 0, 100, 4))  # silent bus: asleep or busy, so leave it alone
            continue
        try:
            power = _vcp(bus, POWER, run)[0]
        except DDC_ERROR:
            power = 1  # it just answered brightness, so 0xD6 is simply unsupported
        out.append(Display(bus, label, cur, mx, power))
    return out


def set_brightness(bus: str, raw: int, run=_ddcutil, run_bus=_busctl) -> None:
    if bus.startswith("backlight:"):
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
