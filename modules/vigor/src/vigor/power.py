"""CPU energy counters, smart plugs and the per-component power model."""
import json
import os
import re
import urllib.request
from dataclasses import dataclass
from pathlib import Path

from .config import Config
from .gpu import GpuReading
from .usage import DiskRate


@dataclass(frozen=True)
class Counter:
    path: Path
    max_uj: int  # 0: 64-bit counter that never wraps in practice


def find_cpu_counters(root: Path) -> list[Counter]:
    for d in sorted((root / "sys/class/hwmon").glob("hwmon*")):
        name_file = d / "name"
        if not name_file.exists() or name_file.read_text().strip() not in ("zenergy", "amd_energy"):
            continue
        socks = [lbl.with_name(lbl.name.replace("_label", "_input"))
                 for lbl in sorted(d.glob("energy*_label")) if lbl.read_text().startswith("Esocket")]
        if socks:
            return [Counter(p, 0) for p in socks]
    out = []
    for d in sorted((root / "sys/class/powercap").glob("intel-rapl:*")):
        energy = d / "energy_uj"
        # Top-level zones are packages; intel-rapl:N:M are subzones already inside them.
        if re.fullmatch(r"intel-rapl:\d+", d.name) and os.access(energy, os.R_OK):
            out.append(Counter(energy, int((d / "max_energy_range_uj").read_text())))
    return out


def read_uj(counters: list[Counter]) -> list[int]:
    return [int(c.path.read_text()) for c in counters]


def cpu_joules(counters: list[Counter], prev: list[int], cur: list[int]) -> float:
    total = 0
    for c, p, n in zip(counters, prev, cur):
        d = n - p
        if d < 0:
            d = d + c.max_uj if c.max_uj else 0
        total += d
    return total / 1e6


PLUG_URLS = {
    "shelly": "http://{host}/rpc/Switch.GetStatus?id=0",
    "tasmota": "http://{host}/cm?cmnd=Status%2010",
}


def parse_shelly(doc: dict) -> float:
    return float(doc["apower"])


def parse_tasmota(doc: dict) -> float:
    return float(doc["StatusSNS"]["ENERGY"]["Power"])


def read_plug(kind: str, host: str, timeout: float = 1.0) -> float | None:
    if kind not in PLUG_URLS or not host:
        return None
    try:
        with urllib.request.urlopen(PLUG_URLS[kind].format(host=host), timeout=timeout) as r:
            doc = json.load(r)
        return parse_shelly(doc) if kind == "shelly" else parse_tasmota(doc)
    except (OSError, ValueError, KeyError):
        return None


@dataclass(frozen=True)
class Inputs:
    cpu_pct: float
    cpu_watts: float | None
    gpus: list[GpuReading]
    disks: list[DiskRate]
    nics: int
    plug_watts: float | None


def _lerp(idle: float, peak: float, pct: float) -> float:
    return idle + (peak - idle) * max(0.0, min(pct, 100.0)) / 100.0


def component_watts(cfg: Config, i: Inputs) -> dict[str, float]:
    cpu = i.cpu_watts if i.cpu_watts is not None else _lerp(cfg.cpu_idle_watts, cfg.cpu_max_watts, i.cpu_pct)
    gpu = sum(g.watts if g.watts is not None else _lerp(cfg.gpu_idle_watts, cfg.gpu_max_watts, g.busy_pct)
              for g in i.gpus)
    disk = sum(_lerp(cfg.disk_watts[d.kind].idle, cfg.disk_watts[d.kind].active, d.busy_pct) for d in i.disks)
    net = cfg.nic_watts * i.nics
    sensed = cpu + gpu + disk + net
    if i.plug_watts is not None:
        # The plug sees the tower at the wall, so the remainder already includes PSU loss.
        board, psu = max(0.0, i.plug_watts - sensed), 0.0
    else:
        board = cfg.base_watts
        dc = sensed + board
        psu = dc / cfg.psu_efficiency - dc
    return {
        "cpu": cpu, "gpu": gpu, "disk": disk, "network": net, "board": board, "psu": psu,
        "extra": sum(x.watts for x in cfg.extra_loads),
    }
