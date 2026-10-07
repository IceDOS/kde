from datetime import date, datetime, timedelta, timezone

from lumen.sun import sun_times


def near(a: datetime, b: datetime, minutes: int) -> bool:
    return abs(a - b) <= timedelta(minutes=minutes)


def test_athens_summer_solstice():
    rise, set_ = sun_times(date(2026, 6, 21), 37.98, 23.73)
    assert near(rise, datetime(2026, 6, 21, 3, 2, tzinfo=timezone.utc), 5)
    assert near(set_, datetime(2026, 6, 21, 17, 51, tzinfo=timezone.utc), 5)


def test_equator_equinox_is_about_six_to_six():
    rise, set_ = sun_times(date(2026, 3, 20), 0.0, 0.0)
    assert near(rise, datetime(2026, 3, 20, 6, 0, tzinfo=timezone.utc), 15)
    assert near(set_, datetime(2026, 3, 20, 18, 0, tzinfo=timezone.utc), 15)


def test_polar_night_and_day():
    rise, set_ = sun_times(date(2026, 12, 21), 69.65, 18.96)
    assert rise == set_ == datetime(2026, 12, 21, 12, 0, tzinfo=timezone.utc)
    rise, set_ = sun_times(date(2026, 6, 21), 69.65, 18.96)
    assert rise == datetime(2026, 6, 21, 0, 0, tzinfo=timezone.utc)
    assert set_ == datetime(2026, 6, 21, 23, 59, tzinfo=timezone.utc)
