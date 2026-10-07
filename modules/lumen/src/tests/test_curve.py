from datetime import date, datetime, timedelta, timezone

import pytest

from lumen.curve import Point, next_point, sample_day, validate_time, value_at

UTC = timezone.utc


def sun(day: date):
    base = datetime(day.year, day.month, day.day, tzinfo=UTC)
    return base + timedelta(hours=6), base + timedelta(hours=20)


def at(h: int, m: int = 0, day: int = 7) -> datetime:
    return datetime(2026, 10, day, h, m, tzinfo=UTC)


PTS = [Point("sunrise", 40), Point("sunrise+60", 80), Point("sunset", 80), Point("22:00", 20)]


@pytest.mark.parametrize("spec", ["07:00", "7:30", "sunrise", "sunset+30", "sunrise-90"])
def test_valid_specs(spec):
    validate_time(spec)


@pytest.mark.parametrize("spec", ["", "25:00", "07:60", "noon", "sunset+", "sunset+1h"])
def test_invalid_specs(spec):
    with pytest.raises(ValueError):
        validate_time(spec)


def test_on_a_point():
    assert value_at(PTS, at(6), sun) == 40


def test_ramp_between_points():
    assert value_at(PTS, at(6, 30), sun) == pytest.approx(60)


def test_wraps_over_midnight():
    # 22:00 (20) to next day's sunrise 06:00 (40): 8 h ramp, 01:00 is 3 h in.
    assert value_at(PTS, at(1), sun) == pytest.approx(20 + 20 * 3 / 8)


def test_single_point_is_flat():
    assert value_at([Point("12:00", 55)], at(3), sun) == 55


def test_next_point_today_and_tomorrow():
    assert next_point(PTS, at(6, 30), sun) == at(7)
    assert next_point(PTS, at(23), sun) == at(6, day=8)


def test_next_point_strictly_after_now():
    assert next_point(PTS, at(6), sun) == at(7)


def test_sample_day_length_and_ends():
    s = sample_day(PTS, at(13), sun)
    assert len(s) == 97
    assert s[24] == pytest.approx(40)  # 06:00
