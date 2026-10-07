import re
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from datetime import date, datetime, timedelta

SunFn = Callable[[date], tuple[datetime, datetime]]

_SPEC = re.compile(r"^(?:(?P<h>\d{1,2}):(?P<m>\d{2})|(?P<sun>sunrise|sunset)(?P<off>[+-]\d+)?)$")


@dataclass(frozen=True)
class Point:
    time: str
    brightness: int


def _match(spec: str) -> re.Match:
    m = _SPEC.match(spec)
    if not m or (m["h"] is not None and (int(m["h"]) > 23 or int(m["m"]) > 59)):
        raise ValueError(f"bad time {spec!r}: use HH:MM, sunrise, sunset, or sunset+30 / sunrise-15 (minutes)")
    return m


def validate_time(spec: str) -> None:
    _match(spec)


def _resolve(p: Point, day: date, now: datetime, sun: SunFn) -> datetime:
    m = _match(p.time)
    if m["h"] is not None:
        return datetime(day.year, day.month, day.day, int(m["h"]), int(m["m"]), tzinfo=now.tzinfo)
    rise, set_ = sun(day)
    base = rise if m["sun"] == "sunrise" else set_
    return base.astimezone(now.tzinfo) + timedelta(minutes=int(m["off"] or 0))


def _timeline(points: Sequence[Point], now: datetime, sun: SunFn) -> list[tuple[datetime, int]]:
    today = now.date()
    days = (today - timedelta(days=1), today, today + timedelta(days=1))
    return sorted(((_resolve(p, d, now, sun), p.brightness) for d in days for p in points), key=lambda t: t[0])


def value_at(points: Sequence[Point], now: datetime, sun: SunFn) -> float:
    tl = _timeline(points, now, sun)
    prev = max((t for t in tl if t[0] <= now), key=lambda t: t[0])
    nxt = min((t for t in tl if t[0] > now), key=lambda t: t[0])
    span = (nxt[0] - prev[0]).total_seconds()
    f = (now - prev[0]).total_seconds() / span if span else 1.0
    return prev[1] + (nxt[1] - prev[1]) * f


def next_point(points: Sequence[Point], now: datetime, sun: SunFn) -> datetime:
    return min(t for t, _ in _timeline(points, now, sun) if t > now)


def sample_day(points: Sequence[Point], now: datetime, sun: SunFn, step_min: int = 15) -> list[float]:
    midnight = now.replace(hour=0, minute=0, second=0, microsecond=0)
    return [round(value_at(points, midnight + timedelta(minutes=i), sun), 1) for i in range(0, 24 * 60 + 1, step_min)]
