import json
from dataclasses import asdict, dataclass, field
from pathlib import Path

from lumen.curve import Point, validate_time

EDIT_KEYS = ("points", "monitors", "latitude", "longitude")


@dataclass(frozen=True)
class Monitor:
    label: str
    enable: bool = True
    scale: float = 1.0
    offset: int = 0
    points: tuple[Point, ...] = ()


@dataclass(frozen=True)
class Config:
    interval: int
    latitude: float
    longitude: float
    min_brightness: int
    tolerance: float
    points: tuple[Point, ...]
    monitors: tuple[Monitor, ...] = field(default=())

    def monitor(self, label: str) -> Monitor:
        return next((m for m in self.monitors if m.label == label), Monitor(label))


def _points(raw: list, where: str, allow_empty: bool) -> tuple[Point, ...]:
    if not raw and not allow_empty:
        raise ValueError(f"{where}: needs at least one point")
    out = []
    for p in raw:
        validate_time(p["time"])
        b = int(p["brightness"])
        if not 0 <= b <= 100:
            raise ValueError(f"{where}: brightness {b} outside 0..100")
        out.append(Point(p["time"], b))
    return tuple(out)


def from_dict(raw: dict) -> Config:
    monitors = []
    for m in raw.get("monitors", []):
        if not m.get("label"):
            raise ValueError("monitors: every entry needs a label")
        monitors.append(
            Monitor(
                label=m["label"],
                enable=bool(m.get("enable", True)),
                scale=float(m.get("scale", 1.0)),
                offset=int(m.get("offset", 0)),
                points=_points(m.get("points", []), f"monitor {m['label']}", allow_empty=True),
            )
        )
    lat, lon = float(raw["latitude"]), float(raw["longitude"])
    if not (-90 <= lat <= 90 and -180 <= lon <= 180):
        raise ValueError(f"location {lat}, {lon}: latitude must be within -90..90, longitude within -180..180")
    return Config(
        interval=int(raw["interval"]),
        latitude=lat,
        longitude=lon,
        min_brightness=int(raw.get("minBrightness", 0)),
        tolerance=float(raw["tolerance"]),
        points=_points(raw["points"], "points", allow_empty=False),
        # Sorted so two configs listing the same monitors compare equal.
        monitors=tuple(sorted(monitors, key=lambda m: m.label)),
    )


def minimal_edits(nix_raw: dict, edits: dict) -> dict:
    """Edits minus anything that matches the Nix config, so an untouched save is a no-op."""
    nix_labels = {m["label"] for m in nix_raw.get("monitors", [])}
    base = from_dict(nix_raw)
    out = {}
    for k in EDIT_KEYS:
        if k not in edits:
            continue
        v = edits[k]
        if k == "monitors":
            v = [m for m in v if m.get("label") in nix_labels or from_dict({**nix_raw, "monitors": [m]}).monitors[0] != Monitor(m["label"])]
        if from_dict({**nix_raw, k: v}) != base:
            out[k] = v
    return out


def load(nix_path: Path, edits_path: Path) -> Config:
    raw = json.loads(nix_path.read_text())
    if edits_path.exists():
        edits = json.loads(edits_path.read_text())
        raw.update({k: edits[k] for k in EDIT_KEYS if k in edits})
    return from_dict(raw)


def to_edit_dict(cfg: Config) -> dict:
    return {
        "points": [asdict(p) for p in cfg.points],
        "monitors": [asdict(m) for m in cfg.monitors],
        "latitude": cfg.latitude,
        "longitude": cfg.longitude,
    }
