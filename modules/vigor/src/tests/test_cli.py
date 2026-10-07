import json

from vigor import cli, config

SNAP = {
    "currency": "€", "total_w": 120.4, "cost_per_hour": 0.0191, "unit_price": 0.159,
    "watts": {"cpu": 30.0, "gpu": 20.0},
    "windows": [{"label": "24h", "wh": 500.0, "cost": 0.08, "by": {}}],
    "all": {"wh": 10000.0, "cost": 1.59, "by": {}},
}


def test_status_json_prints_snapshot(tmp_path, capsys, monkeypatch):
    p = tmp_path / "now.json"
    p.write_text(json.dumps(SNAP))
    monkeypatch.setattr(config, "NOW_PATH", p)
    assert cli.main(["status", "--json"]) == 0
    assert json.loads(capsys.readouterr().out)["total_w"] == 120.4


def test_status_without_daemon(tmp_path, capsys, monkeypatch):
    monkeypatch.setattr(config, "NOW_PATH", tmp_path / "missing.json")
    assert cli.main([]) == 1
    assert "vigor service is not running" in capsys.readouterr().err


def test_format_status():
    out = cli.format_status(SNAP)
    rows = [line.split() for line in out.splitlines()]
    assert out.splitlines()[0] == "120 W  €0.0191/h  (€0.159/kWh)"
    assert ["cpu", "30.0", "W"] in rows
    assert ["24h", "0.50", "kWh", "€0.08"] in rows
    assert ["all", "10.00", "kWh", "€1.59"] in rows
    assert "local AI" not in out


def test_format_status_ai_line():
    ai = {"active": True, "watts": 27.0, "windows": [{"label": "24h", "wh": 30.0, "cost": 0.0123}],
          "all": {"wh": 30.0, "cost": 0.0123}}
    assert cli.format_status({**SNAP, "ai": ai}).splitlines()[-1] == "local AI (part of gpu): 24h €0.01"
