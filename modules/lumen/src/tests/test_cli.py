import json

import pytest

from lumen import cli
from lumen.display import Display

RAW = {
    "interval": 60, "latitude": 0, "longitude": 0, "minBrightness": 5, "tolerance": 2,
    "points": [{"time": "08:00", "brightness": 60}, {"time": "20:00", "brightness": 20}], "monitors": [],
}


@pytest.fixture
def env(tmp_path, monkeypatch):
    nix = tmp_path / "nix.json"
    nix.write_text(json.dumps(RAW))
    monkeypatch.setenv("LUMEN_CONFIG", str(nix))
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path / "state"))
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(tmp_path / "run"))
    calls = []
    monkeypatch.setattr(cli, "list_displays", lambda: [Display("display0", "MG248", 3000, 10000)])
    monkeypatch.setattr(cli, "set_brightness", lambda n, raw: calls.append((n, raw)))
    return tmp_path, calls


def state(tmp_path):
    return json.loads((tmp_path / "state" / "lumen" / "state.json").read_text())


def test_set_writes_and_holds(env):
    tmp_path, calls = env
    assert cli.main(["set", "MG248", "45"]) == 0
    assert calls == [("display0", 4500)]
    s = state(tmp_path)
    assert s["last"]["MG248"] == 45 and "MG248" in s["holds"]


def test_set_zero(env):
    tmp_path, calls = env
    assert cli.main(["set", "MG248", "0"]) == 0
    assert calls == [("display0", 0)]
    s = state(tmp_path)
    assert s["last"]["MG248"] == 0 and "MG248" in s["holds"]


def test_set_unknown_label(env, capsys):
    assert cli.main(["set", "Nope", "45"]) == 1
    assert "Nope" in capsys.readouterr().err


def test_set_all_skips_asleep(env, monkeypatch, capsys):
    tmp_path, calls = env
    monkeypatch.setattr(cli, "list_displays", lambda: [
        Display("6", "MG248", 3000, 10000, 4),
        Display("7", "Mi Monitor", 5000, 10000, 1),
    ])
    assert cli.main(["set", "all", "40"]) == 0
    assert calls == [("7", 4000)]
    assert "skipped asleep: MG248" in capsys.readouterr().err
    s = state(tmp_path)
    assert "Mi Monitor" in s["last"] and "MG248" not in s["last"]


def test_set_asleep_label_fails(env, monkeypatch, capsys):
    tmp_path, calls = env
    monkeypatch.setattr(cli, "list_displays", lambda: [Display("6", "MG248", 3000, 10000, 4)])
    assert cli.main(["set", "MG248", "40"]) == 1
    assert calls == []
    assert "asleep" in capsys.readouterr().err
    assert not (tmp_path / "state" / "lumen" / "state.json").exists()


def test_pause_and_resume(env):
    tmp_path, _ = env
    cli.main(["pause", "forever"])
    assert state(tmp_path)["paused_until"] > 1e15
    cli.main(["resume"])
    assert state(tmp_path)["paused_until"] is None


def test_edit_validates(env, capsys):
    tmp_path, _ = env
    assert cli.main(["edit", json.dumps({"points": [{"time": "noon", "brightness": 5}]})]) == 2
    assert "noon" in capsys.readouterr().err
    assert cli.main(["edit", json.dumps({"points": [{"time": "09:00", "brightness": 50}]})]) == 0
    edits = tmp_path / "state" / "lumen" / "edits.json"
    assert json.loads(edits.read_text())["points"][0]["time"] == "09:00"
    cli.main(["reset"])
    assert not edits.exists()


def test_status_without_daemon(env, capsys):
    assert cli.main(["status", "--json"]) == 1
    assert "not running" in capsys.readouterr().err


def test_edit_equal_to_nix_removes_file(env):
    tmp_path, _ = env
    edits = tmp_path / "state" / "lumen" / "edits.json"
    cli.main(["edit", json.dumps({"points": [{"time": "09:00", "brightness": 50}]})])
    assert edits.exists()
    assert cli.main(["edit", json.dumps({"points": RAW["points"], "monitors": [{"label": "MG248", "offset": 0}]})]) == 0
    assert not edits.exists()
