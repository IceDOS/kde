import json

import pytest

from vigor import store
from vigor.config import Config
from vigor.gpu import GpuReading
from vigor.meter import Meter, write_snapshot


def machine(root, put, *, user, idle, uj, busy):
    put("proc/stat", f"cpu  {user} 0 0 {idle} 0 0 0 0 0 0\n")
    put("proc/diskstats", f" 259 0 nvme0n1 0 0 0 0 0 0 0 0 0 {busy} 0\n")
    (root / "sys/block/nvme0n1/device").mkdir(parents=True, exist_ok=True)
    put("proc/net/dev", "h\nh\n  eth0: 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0\n")
    (root / "sys/class/net/eth0/device").mkdir(parents=True, exist_ok=True)
    put("sys/class/hwmon/hwmon0/name", "zenergy\n")
    put("sys/class/hwmon/hwmon0/energy1_label", "Esocket0\n")
    put("sys/class/hwmon/hwmon0/energy1_input", f"{uj}\n")


def test_tick_measures_and_integrates(tmp_path, put):
    machine(tmp_path, put, user=100, idle=900, uj=5_000_000, busy=0)
    times = iter([1000.0, 1002.0])
    con = store.connect(tmp_path / "db.sqlite")
    gpus = [GpuReading("card1", 17.0, 37.0)]
    m = Meter(Config(), con, root=tmp_path, clock=lambda: next(times), read_gpus=lambda: gpus)
    machine(tmp_path, put, user=300, idle=1700, uj=65_000_000, busy=1000)

    snap = m.tick()

    assert snap["cpu_source"] == "counter"
    assert snap["watts"]["cpu"] == pytest.approx(30.0)
    assert snap["usage"]["cpu_pct"] == pytest.approx(20.0)
    assert snap["watts"]["disk"] == pytest.approx(3.0)
    assert snap["watts"]["network"] == 1.0
    assert snap["gpus"] == [{"card": "card1", "busy_pct": 17.0, "watts": 37.0}]
    assert snap["total_w"] == pytest.approx(sum(snap["watts"].values()))
    m.flush(1002.0)
    assert m.all["by"]["cpu"]["wh"] == pytest.approx(30 * 2 / 3600)
    assert [w["label"] for w in m.window_totals] == ["1h", "24h", "7d", "30d"]
    assert m.window_totals[0]["by"]["gpu"]["wh"] == pytest.approx(37 * 2 / 3600)
    assert snap["ai"]["active"] is False and "ai" not in m.all["by"]


def test_ai_gets_gpu_draw_above_idle(tmp_path, put):
    machine(tmp_path, put, user=1, idle=1, uj=0, busy=0)
    times = iter([1000.0, 1002.0])
    con = store.connect(tmp_path / "db.sqlite")
    gpus = [GpuReading("card1", 90.0, 37.0)]
    m = Meter(Config(gpu_idle_watts=10.0), con, root=tmp_path, clock=lambda: next(times),
              read_gpus=lambda: gpus, ai_active=lambda: True)
    snap = m.tick()
    assert (snap["ai"]["active"], snap["ai"]["watts"]) == (True, pytest.approx(27.0))
    m.flush(1002.0)
    assert m.window_totals[0]["by"]["ai"]["wh"] == pytest.approx(27 * 2 / 3600)
    assert m.all["wh"] == pytest.approx(sum(v["wh"] for c, v in m.all["by"].items() if c != "ai"))


def test_startup_bills_gap_as_standby(tmp_path, put):
    machine(tmp_path, put, user=1, idle=1, uj=0, busy=0)
    con = store.connect(tmp_path / "db.sqlite")
    store.set_meta(con, "last_ts", 1000.0 - 3600)
    m = Meter(Config(standby_watts=2.0), con, root=tmp_path, clock=lambda: 1000.0, read_gpus=lambda: [])
    assert m.all["by"]["standby"]["wh"] == pytest.approx(2.0)


def test_long_tick_counts_as_standby(tmp_path, put):
    machine(tmp_path, put, user=1, idle=1, uj=0, busy=0)
    times = iter([1000.0, 1000.0 + 1800])
    con = store.connect(tmp_path / "db.sqlite")
    m = Meter(Config(standby_watts=2.0), con, root=tmp_path, clock=lambda: next(times), read_gpus=lambda: [])
    assert m.tick() is None
    assert m.all["by"]["standby"]["wh"] == pytest.approx(1.0)


def test_write_snapshot_is_atomic_json(tmp_path):
    p = tmp_path / "run/now.json"
    write_snapshot(p, {"total_w": 5})
    assert json.loads(p.read_text()) == {"total_w": 5}
    assert not list(p.parent.glob("*.tmp"))
