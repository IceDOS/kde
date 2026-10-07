"""Turns counter deltas into watts, Wh and cost per component and builds the snapshot."""
import json
import os
import time
from collections import deque
from datetime import datetime
from pathlib import Path

from . import gpu, power, store, tariff, usage, windows
from .config import Config

FLUSH_S = 30
HISTORY = 150
ZERO = {"wh": 0.0, "cost": 0.0}


def write_snapshot(path: Path, snap: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(snap))
    os.chmod(tmp, 0o644)
    os.replace(tmp, path)


class Meter:
    def __init__(self, cfg: Config, con, root: Path = Path("/"), clock=time.time, read_gpus=None, ai_active=None):
        self.cfg, self.con, self.root, self.clock = cfg, con, root, clock
        self.ai_active = ai_active or (lambda: False)
        self.read_gpus = read_gpus or (lambda: gpu.read_amdgpu(root) or gpu.read_nvidia())
        self.counters = power.find_cpu_counters(root)
        self.pending: dict[tuple[int, str], list[float]] = {}
        self.history: deque = deque(maxlen=HISTORY)
        self.prev = self._snapshot()
        last = store.get_meta_float(con, "last_ts")
        if last is not None:
            self._standby(last, self.prev["t"])
        self.flush(self.prev["t"])

    def _snapshot(self) -> dict:
        return {
            "t": self.clock(),
            "cpu": usage.read_cpu(self.root),
            "disks": usage.read_disks(self.root),
            "net": usage.read_net(self.root),
            "uj": power.read_uj(self.counters),
        }

    def _add(self, t: float, component: str, wh: float) -> None:
        acc = self.pending.setdefault((int(t // 60), component), [0.0, 0.0])
        acc[0] += wh
        acc[1] += tariff.cost(self.cfg, wh, datetime.fromtimestamp(t))

    def _standby(self, start: float, end: float) -> bool:
        # A gap of several intervals means suspend or power-off; billed at the end time's price.
        if end - start <= 3 * self.cfg.interval:
            return False
        self._add(end, "standby", self.cfg.standby_watts * (end - start) / 3600)
        return True

    def flush(self, t: float) -> None:
        if self.pending:
            store.add(self.con, {k: (v[0], v[1]) for k, v in self.pending.items()})
            self.pending.clear()
        store.set_meta(self.con, "last_ts", t)
        self.last_flush = t
        now = datetime.fromtimestamp(t)
        # Floored to the minute, so the bucket straddling the window start counts whole (as in power.ts).
        self.window_totals = [
            {"label": label, **store.totals(self.con, int(windows.start(label, now).timestamp() // 60))}
            for label in self.cfg.windows
        ]
        self.all = store.totals(self.con, 0)

    def tick(self) -> dict | None:
        cur = self._snapshot()
        prev, self.prev = self.prev, cur
        dt = cur["t"] - prev["t"]
        if dt <= 0:
            return None
        if self._standby(prev["t"], cur["t"]):
            self.flush(cur["t"])
            return None

        cpu_w = power.cpu_joules(self.counters, prev["uj"], cur["uj"]) / dt if self.counters else None
        cpu_pct = usage.cpu_percent(prev["cpu"], cur["cpu"])
        gpus = self.read_gpus()
        disks = usage.disk_rates(prev["disks"], cur["disks"], dt)
        rx, tx = usage.net_rates(prev["net"], cur["net"], dt)
        plug_w = power.read_plug(self.cfg.plug_type, self.cfg.plug_host)
        watts = power.component_watts(self.cfg, power.Inputs(
            cpu_pct=cpu_pct, cpu_watts=cpu_w, gpus=gpus, disks=disks, nics=len(cur["net"]),
            plug_watts=plug_w,
        ))
        for c, w in watts.items():
            self._add(cur["t"], c, w * dt / 3600)
        # A local-model request owns the GPU draw above idle, as prime-agent's own meter counts it.
        active = self.ai_active()
        ai_w = max(0.0, watts["gpu"] - self.cfg.gpu_idle_watts) if active else 0.0
        if ai_w:
            self._add(cur["t"], "ai", ai_w * dt / 3600)
        if cur["t"] - self.last_flush >= FLUSH_S:
            self.flush(cur["t"])

        total = sum(watts.values())
        self.history.append(round(total, 1))
        price = tariff.unit_price(self.cfg, datetime.fromtimestamp(cur["t"]))
        return {
            "ts": cur["t"], "interval": self.cfg.interval, "currency": self.cfg.currency,
            "unit_price": price, "total_w": total, "cost_per_hour": total / 1000 * price,
            "cpu_source": "counter" if self.counters else "model", "plug": plug_w is not None,
            "watts": watts,
            "gpus": [{"card": g.card, "busy_pct": g.busy_pct, "watts": g.watts} for g in gpus],
            "usage": {
                "cpu_pct": cpu_pct,
                "gpu_pct": max((g.busy_pct for g in gpus), default=0.0),
                "disk_read_bps": sum(d.read_bps for d in disks),
                "disk_write_bps": sum(d.write_bps for d in disks),
                "net_rx_bps": rx, "net_tx_bps": tx,
            },
            "component_window": self.cfg.component_window,
            "windows": self.window_totals,
            "all": self.all,
            "ai": {
                "active": active, "watts": ai_w,
                "windows": [{"label": w["label"], **w["by"].get("ai", ZERO)} for w in self.window_totals],
                "all": {**self.all["by"].get("ai", ZERO)},
            },
            "history": list(self.history),
        }
