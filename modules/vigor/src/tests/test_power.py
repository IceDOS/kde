import pytest

from vigor import power
from vigor.config import Config, Load
from vigor.gpu import GpuReading
from vigor.usage import DiskRate


def test_zenergy_uses_socket_counters_only(tmp_path, put):
    put("sys/class/hwmon/hwmon2/name", "zenergy\n")
    put("sys/class/hwmon/hwmon2/energy1_label", "Ecore000\n")
    put("sys/class/hwmon/hwmon2/energy1_input", "1\n")
    put("sys/class/hwmon/hwmon2/energy7_label", "Esocket0\n")
    put("sys/class/hwmon/hwmon2/energy7_input", "5000000\n")
    (c,) = power.find_cpu_counters(tmp_path)
    assert c.path.name == "energy7_input" and c.max_uj == 0
    assert power.read_uj([c]) == [5_000_000]


def test_rapl_packages_with_wrap(tmp_path, put):
    put("sys/class/powercap/intel-rapl:0/energy_uj", "900\n")
    put("sys/class/powercap/intel-rapl:0/max_energy_range_uj", "1000\n")
    put("sys/class/powercap/intel-rapl:0:0/energy_uj", "1\n")
    (c,) = power.find_cpu_counters(tmp_path)
    assert c.max_uj == 1000
    assert power.cpu_joules([c], [900], [100]) == pytest.approx(200e-6)


def test_cpu_joules_sums_sockets():
    cs = [power.Counter(None, 0), power.Counter(None, 0)]
    assert power.cpu_joules(cs, [0, 0], [30_000_000, 30_000_000]) == pytest.approx(60.0)


def test_plug_parsers():
    assert power.parse_shelly({"id": 0, "apower": 98.4}) == 98.4
    assert power.parse_tasmota({"StatusSNS": {"ENERGY": {"Power": 101}}}) == 101.0
    assert power.read_plug("none", "10.0.0.5") is None


def _inputs(**kw):
    base = dict(cpu_pct=0.0, cpu_watts=30.0, gpus=[GpuReading("card1", 10.0, 20.0)],
                disks=[DiskRate("nvme0n1", "nvme", 0, 0, 50.0)], nics=1, plug_watts=None)
    base.update(kw)
    return power.Inputs(**base)


def test_model_without_plug():
    w = power.component_watts(Config(extra_loads=(Load("Speakers", 8),)), _inputs())
    assert list(w) == ["cpu", "gpu", "disk", "network", "board", "psu", "extra"]
    assert (w["cpu"], w["gpu"], w["disk"], w["network"], w["board"]) == (30.0, 20.0, 3.0, 1.0, 25.0)
    assert w["psu"] == pytest.approx(79 / 0.88 - 79)
    assert w["extra"] == 8.0


def test_model_falls_back_to_lerp():
    w = power.component_watts(Config(), _inputs(cpu_watts=None, cpu_pct=50.0, gpus=[GpuReading("card1", 100.0, None)]))
    assert w["cpu"] == pytest.approx(15 + 73 * 0.5)
    assert w["gpu"] == pytest.approx(150.0)


def test_plug_replaces_board_and_psu_estimate():
    w = power.component_watts(Config(), _inputs(plug_watts=100.0))
    assert w["board"] == pytest.approx(100 - 54)
    assert w["psu"] == 0.0
