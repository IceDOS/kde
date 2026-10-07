import json

import pytest

from lumen.config import Monitor, from_dict, load, minimal_edits, to_edit_dict
from lumen.curve import Point

RAW = {
    "interval": 60,
    "latitude": 37.98,
    "longitude": 23.73,
    "minBrightness": 5,
    "tolerance": 2,
    "points": [{"time": "sunrise", "brightness": 70}, {"time": "22:00", "brightness": 20}],
    "monitors": [{"label": "MG248", "enable": True, "scale": 1.0, "offset": -10, "points": []}],
}


def test_from_dict():
    cfg = from_dict(RAW)
    assert cfg.points == (Point("sunrise", 70), Point("22:00", 20))
    assert cfg.monitor("MG248").offset == -10
    assert cfg.monitor("Unknown") == Monitor("Unknown")


@pytest.mark.parametrize(
    "patch",
    [
        {"points": []},
        {"points": [{"time": "noon", "brightness": 50}]},
        {"points": [{"time": "07:00", "brightness": 101}]},
        {"monitors": [{"label": "", "points": []}]},
    ],
)
def test_rejects_bad_input(patch):
    with pytest.raises(ValueError):
        from_dict({**RAW, **patch})


def test_edits_override_points_and_monitors(tmp_path):
    nix = tmp_path / "nix.json"
    nix.write_text(json.dumps(RAW))
    edits = tmp_path / "edits.json"
    edits.write_text(json.dumps({"points": [{"time": "08:00", "brightness": 50}], "interval": 1}))
    cfg = load(nix, edits)
    assert cfg.points == (Point("08:00", 50),)
    assert cfg.interval == 60  # only points/monitors are editable
    assert cfg.monitor("MG248").offset == -10


def test_missing_edits_file(tmp_path):
    nix = tmp_path / "nix.json"
    nix.write_text(json.dumps(RAW))
    assert load(nix, tmp_path / "none.json").points[0] == Point("sunrise", 70)


def test_to_edit_dict_round_trips():
    cfg = from_dict(RAW)
    assert from_dict({**RAW, **to_edit_dict(cfg)}) == cfg


def test_location_is_editable(tmp_path):
    nix = tmp_path / "nix.json"
    nix.write_text(json.dumps(RAW))
    edits = tmp_path / "edits.json"
    edits.write_text(json.dumps({"latitude": 44.43, "longitude": 26.1}))
    cfg = load(nix, edits)
    assert (cfg.latitude, cfg.longitude) == (44.43, 26.1)


@pytest.mark.parametrize("patch", [{"latitude": 91}, {"longitude": -181}])
def test_rejects_bad_location(patch):
    with pytest.raises(ValueError):
        from_dict({**RAW, **patch})


def test_minimal_edits_drops_values_equal_to_nix():
    same = {
        "points": RAW["points"],
        "latitude": RAW["latitude"],
        # Widget writes untouched monitors with default settings.
        "monitors": RAW["monitors"] + [{"label": "Mi Monitor", "enable": True, "scale": 1, "offset": 0, "points": []}],
    }
    assert minimal_edits(RAW, same) == {}


def test_minimal_edits_keeps_real_changes():
    edits = {"longitude": 0.0, "monitors": [{"label": "Mi Monitor", "enable": True, "scale": 1, "offset": -20, "points": []}]}
    out = minimal_edits(RAW, edits)
    assert out["longitude"] == 0.0
    assert any(m["label"] == "Mi Monitor" for m in out["monitors"])


def test_monitor_order_does_not_matter():
    two = [{"label": "B", "offset": 5}, {"label": "A", "offset": 5}]
    assert from_dict({**RAW, "monitors": two}) == from_dict({**RAW, "monitors": two[::-1]})
