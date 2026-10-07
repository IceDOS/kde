import pytest

from vigor import usage


def test_cpu_percent_excludes_idle_and_iowait(tmp_path, put):
    put("proc/stat", "cpu  100 0 50 800 50 0 0 0 0 0\ncpu0 1 1 1 1 1 0 0 0 0 0\n")
    a = usage.read_cpu(tmp_path)
    put("proc/stat", "cpu  200 0 100 1500 100 0 0 0 0 0\n")
    b = usage.read_cpu(tmp_path)
    assert (a.busy, a.total) == (150, 1000)
    assert usage.cpu_percent(a, b) == pytest.approx(150 / 900 * 100)


def test_cpu_percent_zero_delta():
    t = usage.CpuTimes(1, 2)
    assert usage.cpu_percent(t, t) == 0.0


def test_disks_skip_partitions_and_virtual(tmp_path, put):
    put("proc/diskstats",
        " 259 0 nvme0n1 1000 0 2048 0 500 0 4096 0 0 300 0\n"
        " 259 1 nvme0n1p1 1 0 8 0 1 0 8 0 0 1 0\n"
        " 252 0 zram0 1 0 8 0 1 0 8 0 0 1 0\n"
        "   8 32 sdc 1 0 8 0 1 0 8 0 0 1 0\n")
    (tmp_path / "sys/block/nvme0n1/device").mkdir(parents=True)
    (tmp_path / "sys/block/sdc/device").mkdir(parents=True)
    put("sys/block/sdc/queue/rotational", "1\n")
    (tmp_path / "sys/block/zram0").mkdir(parents=True)
    d = usage.read_disks(tmp_path)
    assert set(d) == {"nvme0n1", "sdc"}
    assert d["nvme0n1"].kind == "nvme" and d["sdc"].kind == "hdd"
    assert d["nvme0n1"].read_bytes == 2048 * 512
    assert d["nvme0n1"].busy_ms == 300


def test_disk_rates():
    a = {"sda": usage.DiskStat("sda", "ssd", 0, 0, 300)}
    b = {"sda": usage.DiskStat("sda", "ssd", 1_048_576, 2_097_152, 1300)}
    (r,) = usage.disk_rates(a, b, 2.0)
    assert r.read_bps == 524_288 and r.write_bps == 1_048_576
    assert r.busy_pct == pytest.approx(50.0)


def test_net_counts_physical_nics_only(tmp_path, put):
    put("proc/net/dev",
        "Inter-|   Receive\n face |bytes\n"
        "  eth0: 1000 10 0 0 0 0 0 0 2000 20 0 0 0 0 0 0\n"
        "    lo: 500 5 0 0 0 0 0 0 500 5 0 0 0 0 0 0\n"
        "proton0: 9 9 0 0 0 0 0 0 9 9 0 0 0 0 0 0\n")
    (tmp_path / "sys/class/net/eth0/device").mkdir(parents=True)
    a = usage.read_net(tmp_path)
    assert a == {"eth0": (1000, 2000)}
    assert usage.net_rates(a, {"eth0": (3000, 2500)}, 2.0) == (1000.0, 250.0)
