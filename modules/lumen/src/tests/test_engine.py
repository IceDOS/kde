from datetime import date, datetime, timedelta, timezone

import pytest

from lumen.config import Config, Monitor
from lumen.curve import Point
from lumen.display import Display
from lumen.engine import tick
from lumen.state import FOREVER, State

UTC = timezone.utc
NOW = datetime(2026, 10, 7, 12, 0, tzinfo=UTC)


def sun(day: date):
    base = datetime(day.year, day.month, day.day, tzinfo=UTC)
    return base + timedelta(hours=6), base + timedelta(hours=20)


def cfg(**kw):
    base = dict(
        interval=60, latitude=0, longitude=0, min_brightness=0, tolerance=2,
        points=(Point("08:00", 60), Point("16:00", 60), Point("20:00", 20)), monitors=(),
    )
    return Config(**{**base, **kw})


def disp(pct, name="display0", label="A", power=1):
    return Display(name, label, int(pct * 100), 10000, power)


class Rec:
    def __init__(self):
        self.calls = []

    def __call__(self, name, raw):
        self.calls.append((name, raw))


def test_sets_scheduled_value():
    st, rec = State(), Rec()
    out = tick(cfg(), st, [disp(30)], NOW, sun, rec)
    assert rec.calls == [("display0", 6000)]
    assert st.last["A"] == 60
    assert out["monitors"][0]["target"] == 60


def test_no_write_when_already_there():
    rec = Rec()
    tick(cfg(), State(last={"A": 60}), [disp(60)], NOW, sun, rec)
    assert rec.calls == []


def test_manual_change_holds_until_next_point():
    st, rec = State(last={"A": 60}), Rec()
    out = tick(cfg(), st, [disp(30)], NOW, sun, rec)
    assert rec.calls == []
    assert st.holds["A"] == datetime(2026, 10, 7, 16, 0, tzinfo=UTC).timestamp()
    assert out["monitors"][0]["held_until"] == st.holds["A"]


def test_hold_expires():
    st, rec = State(last={"A": 30}, holds={"A": NOW.timestamp() - 1}), Rec()
    tick(cfg(), st, [disp(30)], NOW, sun, rec)
    assert rec.calls == [("display0", 6000)]
    assert "A" not in st.holds


def test_paused_does_nothing():
    rec = Rec()
    tick(cfg(), State(paused_until=FOREVER, last={"A": 30}), [disp(30)], NOW, sun, rec)
    assert rec.calls == []


def test_expired_pause_clears():
    st, rec = State(paused_until=NOW.timestamp() - 1, last={"A": 30}), Rec()
    tick(cfg(), st, [disp(30)], NOW, sun, rec)
    assert st.paused_until is None and rec.calls


def test_monitor_scale_offset_and_clamp():
    c = cfg(monitors=(Monitor("A", scale=0.5, offset=-40),))
    rec = Rec()
    tick(c, State(), [disp(30)], NOW, sun, rec)
    assert rec.calls == [("display0", 0)]  # 60*0.5-40 = -10, clamped to min 0


def test_custom_min_brightness():
    c = cfg(min_brightness=5, monitors=(Monitor("A", scale=0.5, offset=-40),))
    rec = Rec()
    tick(c, State(), [disp(30)], NOW, sun, rec)
    assert rec.calls == [("display0", 500)]  # 60*0.5-40 = -10, clamped to min 5


def test_schedule_can_reach_zero():
    c = cfg(points=(Point("00:00", 0), Point("23:59", 0)))
    rec = Rec()
    tick(c, State(), [disp(30)], NOW, sun, rec)
    assert rec.calls == [("display0", 0)]


def test_monitor_own_points():
    c = cfg(monitors=(Monitor("A", points=(Point("00:00", 25),)),))
    rec = Rec()
    tick(c, State(), [disp(30)], NOW, sun, rec)
    assert rec.calls == [("display0", 2500)]


def test_disabled_monitor_untouched_and_tracked():
    c = cfg(monitors=(Monitor("A", enable=False),))
    st, rec = State(last={"A": 60}), Rec()
    tick(c, st, [disp(30)], NOW, sun, rec)
    assert rec.calls == [] and st.last["A"] == 30 and "A" not in st.holds


def test_asleep_display_is_left_alone():
    st, rec = State(last={"A": 60}), Rec()
    out = tick(cfg(), st, [disp(30, power=4)], NOW, sun, rec)
    assert rec.calls == []
    assert st.last["A"] == 60 and not st.holds
    assert out["monitors"][0]["awake"] is False
    assert out["monitors"][0]["target"] == 60


def test_awake_display_is_reported_as_such():
    out = tick(cfg(), State(), [disp(60)], NOW, sun, Rec())
    assert out["monitors"][0]["awake"] is True


def test_setter_error_reported():
    def boom(name, raw):
        raise RuntimeError("dbus down")

    out = tick(cfg(), State(), [disp(30)], NOW, sun, boom)
    assert "dbus down" in out["monitors"][0]["error"]


def test_status_shape():
    out = tick(cfg(), State(), [disp(60)], NOW, sun, Rec())
    assert out["next"] == {"at": "16:00", "brightness": 60}
    assert out["sunrise"] == "06:00" and out["sunset"] == "20:00"
    assert len(out["monitors"][0]["curve"]) == 97
    assert out["config"]["points"][0] == {"time": "08:00", "brightness": 60}
