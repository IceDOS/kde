"""Runtime settings from the JSON file the Nix module writes, plus paths."""
import json
import os
import re
from dataclasses import dataclass, field, fields
from pathlib import Path

# systemd sets these from StateDirectory= and RuntimeDirectory=; the CLI falls back to the same paths.
DB_PATH = Path(os.environ.get("STATE_DIRECTORY", "/var/lib/vigor")) / "vigor.db"
NOW_PATH = Path(os.environ.get("RUNTIME_DIRECTORY", "/run/vigor")) / "now.json"
# prime-agent touches one file here per in-flight local-model request (Task 9).
LEASE_DIR = NOW_PATH.parent / "ai"


@dataclass(frozen=True)
class Band:
    start: str  # local "HH:MM"
    end: str
    price: float


@dataclass(frozen=True)
class Load:
    name: str
    watts: float


@dataclass(frozen=True)
class DiskWatts:
    idle: float
    active: float


def _default_disks() -> dict:
    return {"nvme": DiskWatts(1.0, 5.0), "ssd": DiskWatts(0.5, 3.0), "hdd": DiskWatts(4.0, 7.0)}


@dataclass(frozen=True)
class Config:
    interval: float = 2.0
    currency: str = "€"
    price: float = 0.15
    surcharge: float = 0.0
    vat: float = 6.0
    bands: tuple = ()
    psu_efficiency: float = 0.88
    base_watts: float = 25.0
    nic_watts: float = 1.0
    standby_watts: float = 2.0
    cpu_idle_watts: float = 15.0
    cpu_max_watts: float = 88.0
    gpu_idle_watts: float = 10.0
    gpu_max_watts: float = 150.0
    disk_watts: dict = field(default_factory=_default_disks)
    extra_loads: tuple = ()
    plug_type: str = "none"
    plug_host: str = ""
    windows: tuple = ("1h", "24h", "7d", "30d")
    component_window: str = "24h"


def _snake(k: str) -> str:
    return re.sub(r"(?<!^)(?=[A-Z])", "_", k).lower()


def from_dict(d: dict) -> Config:
    raw = {_snake(k): v for k, v in d.items()}
    plug = raw.pop("plug", {})
    raw["plug_type"] = plug.get("type", "none")
    raw["plug_host"] = plug.get("host", "")
    if "bands" in raw:
        raw["bands"] = tuple(Band(**b) for b in raw["bands"])
    if "extra_loads" in raw:
        raw["extra_loads"] = tuple(Load(**x) for x in raw["extra_loads"])
    if "disk_watts" in raw:
        raw["disk_watts"] = {k: DiskWatts(**v) for k, v in raw["disk_watts"].items()}
    if "windows" in raw:
        raw["windows"] = tuple(raw["windows"])
    known = {f.name for f in fields(Config)}
    return Config(**{k: v for k, v in raw.items() if k in known})


def load(path: Path | None) -> Config:
    if path is None:
        return Config()
    return from_dict(json.loads(Path(path).read_text()))
