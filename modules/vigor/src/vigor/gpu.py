"""GPU utilization and board power: amdgpu through sysfs, NVIDIA through nvidia-smi."""
import re
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class GpuReading:
    card: str
    busy_pct: float
    watts: float | None


def read_amdgpu(root: Path) -> list[GpuReading]:
    out = []
    for card in sorted((root / "sys/class/drm").glob("card*")):
        busy = card / "device/gpu_busy_percent"
        if not re.fullmatch(r"card\d+", card.name) or not busy.exists():
            continue
        watts = None
        for name in ("power1_average", "power1_input"):
            hits = sorted((card / "device").glob(f"hwmon/hwmon*/{name}"))
            if hits:
                watts = int(hits[0].read_text()) / 1e6
                break
        out.append(GpuReading(card.name, float(busy.read_text()), watts))
    return out


def parse_nvidia_smi(text: str) -> list[GpuReading]:
    out = []
    for i, line in enumerate(text.strip().splitlines()):
        util, power = (x.strip() for x in line.split(","))
        out.append(GpuReading(f"nvidia{i}", float(util), None if "N/A" in power else float(power)))
    return out


def read_nvidia() -> list[GpuReading]:
    exe = shutil.which("nvidia-smi")
    if not exe:
        return []
    try:
        r = subprocess.run([exe, "--query-gpu=utilization.gpu,power.draw", "--format=csv,noheader,nounits"],
                           capture_output=True, text=True, timeout=2)
    except (OSError, subprocess.TimeoutExpired):
        return []
    return parse_nvidia_smi(r.stdout) if r.returncode == 0 else []
