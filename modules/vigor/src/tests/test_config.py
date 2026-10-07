import json

from vigor import config


def test_defaults_without_file():
    cfg = config.load(None)
    assert cfg.interval == 2.0
    assert cfg.disk_watts["hdd"] == config.DiskWatts(4.0, 7.0)
    assert cfg.plug_type == "none"


def test_camel_case_keys_from_nix(tmp_path):
    p = tmp_path / "c.json"
    p.write_text(json.dumps({
        "psuEfficiency": 0.9,
        "baseWatts": 30,
        "bands": [{"start": "23:00", "end": "07:00", "price": 0.08}],
        "extraLoads": [{"name": "Speakers", "watts": 12}],
        "diskWatts": {"nvme": {"idle": 2, "active": 6}, "ssd": {"idle": 1, "active": 3}, "hdd": {"idle": 5, "active": 8}},
        "plug": {"type": "shelly", "host": "10.0.0.5"},
        "windows": ["15m", "1M"],
        "componentWindow": "1M",
        "widget": True,
    }))
    cfg = config.load(p)
    assert cfg.psu_efficiency == 0.9
    assert cfg.base_watts == 30
    assert cfg.bands == (config.Band("23:00", "07:00", 0.08),)
    assert cfg.extra_loads == (config.Load("Speakers", 12),)
    assert cfg.disk_watts["nvme"] == config.DiskWatts(2, 6)
    assert (cfg.plug_type, cfg.plug_host) == ("shelly", "10.0.0.5")
    assert (cfg.windows, cfg.component_window) == (("15m", "1M"), "1M")
