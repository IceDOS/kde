import pytest

from vigor import store


def test_add_accumulates_same_minute(tmp_path):
    con = store.connect(tmp_path / "x.db")
    store.add(con, {(100, "cpu"): (1.0, 0.1)})
    store.add(con, {(100, "cpu"): (2.0, 0.2), (100, "gpu"): (4.0, 0.4)})
    store.add(con, {(50, "cpu"): (9.0, 0.9)})
    t = store.totals(con, 100)
    assert t["wh"] == pytest.approx(7.0)
    assert t["cost"] == pytest.approx(0.7)
    assert t["by"]["cpu"] == {"wh": pytest.approx(3.0), "cost": pytest.approx(0.3)}


def test_ai_is_listed_but_not_added(tmp_path):
    con = store.connect(tmp_path / "x.db")
    store.add(con, {(100, "gpu"): (4.0, 0.4), (100, "ai"): (3.0, 0.3)})
    t = store.totals(con, 0)
    assert (t["wh"], t["cost"]) == (pytest.approx(4.0), pytest.approx(0.4))
    assert t["by"]["ai"]["wh"] == pytest.approx(3.0)


def test_meta_roundtrip(tmp_path):
    con = store.connect(tmp_path / "x.db")
    assert store.get_meta_float(con, "last_ts") is None
    store.set_meta(con, "last_ts", 12.5)
    assert store.get_meta_float(con, "last_ts") == 12.5
