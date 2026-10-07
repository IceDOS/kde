"""Utilization counters from /proc and /sys. Every reader takes `root` so tests can fake the tree."""
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class CpuTimes:
    busy: int
    total: int


def read_cpu(root: Path) -> CpuTimes:
    # user nice system idle iowait irq softirq steal; guest time is already inside user.
    vals = [int(x) for x in (root / "proc/stat").read_text().split("\n", 1)[0].split()[1:9]]
    idle = vals[3] + vals[4]
    return CpuTimes(sum(vals) - idle, sum(vals))


def cpu_percent(prev: CpuTimes, cur: CpuTimes) -> float:
    dt = cur.total - prev.total
    return 0.0 if dt <= 0 else 100.0 * (cur.busy - prev.busy) / dt


@dataclass(frozen=True)
class DiskStat:
    name: str
    kind: str
    read_bytes: int
    write_bytes: int
    busy_ms: int


@dataclass(frozen=True)
class DiskRate:
    name: str
    kind: str
    read_bps: float
    write_bps: float
    busy_pct: float


def _disk_kind(root: Path, name: str) -> str:
    if name.startswith("nvme"):
        return "nvme"
    rot = root / "sys/block" / name / "queue/rotational"
    return "hdd" if rot.exists() and rot.read_text().strip() == "1" else "ssd"


def read_disks(root: Path) -> dict[str, DiskStat]:
    out = {}
    for line in (root / "proc/diskstats").read_text().splitlines():
        f = line.split()
        name = f[2]
        # Whole physical disks only: partitions, zram and loop have no sys/block/<name>/device.
        if not (root / "sys/block" / name / "device").exists():
            continue
        out[name] = DiskStat(name, _disk_kind(root, name), int(f[5]) * 512, int(f[9]) * 512, int(f[12]))
    return out


def disk_rates(prev: dict[str, DiskStat], cur: dict[str, DiskStat], dt_s: float) -> list[DiskRate]:
    out = []
    if dt_s <= 0:
        return out
    for name, c in cur.items():
        p = prev.get(name)
        if p is None:
            continue
        busy = min(100.0, 100.0 * (c.busy_ms - p.busy_ms) / (dt_s * 1000))
        out.append(DiskRate(name, c.kind, (c.read_bytes - p.read_bytes) / dt_s,
                            (c.write_bytes - p.write_bytes) / dt_s, busy))
    return out


def read_net(root: Path) -> dict[str, tuple[int, int]]:
    out = {}
    for line in (root / "proc/net/dev").read_text().splitlines()[2:]:
        name, data = line.split(":", 1)
        name = name.strip()
        # Physical NICs only, so VPN tunnels and bridges don't count traffic twice.
        if not (root / "sys/class/net" / name / "device").exists():
            continue
        f = data.split()
        out[name] = (int(f[0]), int(f[8]))
    return out


def net_rates(prev: dict, cur: dict, dt_s: float) -> tuple[float, float]:
    rx = tx = 0.0
    if dt_s <= 0:
        return rx, tx
    for name, (r, t) in cur.items():
        if name in prev:
            rx += (r - prev[name][0]) / dt_s
            tx += (t - prev[name][1]) / dt_s
    return rx, tx
