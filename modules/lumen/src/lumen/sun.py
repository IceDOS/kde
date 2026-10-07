import math
from datetime import date, datetime, timedelta, timezone

# Sun centre 50' below the horizon: refraction plus the disc radius.
ZENITH = 90.833


def _utc_minutes(day: date, lat: float, lon: float, rising: bool) -> float | str:
    gamma = 2 * math.pi / 365 * (day.timetuple().tm_yday - 1)
    eqtime = 229.18 * (
        0.000075
        + 0.001868 * math.cos(gamma)
        - 0.032077 * math.sin(gamma)
        - 0.014615 * math.cos(2 * gamma)
        - 0.040849 * math.sin(2 * gamma)
    )
    decl = (
        0.006918
        - 0.399912 * math.cos(gamma)
        + 0.070257 * math.sin(gamma)
        - 0.006758 * math.cos(2 * gamma)
        + 0.000907 * math.sin(2 * gamma)
        - 0.002697 * math.cos(3 * gamma)
        + 0.00148 * math.sin(3 * gamma)
    )
    lat_r = math.radians(lat)
    cos_ha = math.cos(math.radians(ZENITH)) / (math.cos(lat_r) * math.cos(decl)) - math.tan(lat_r) * math.tan(decl)
    if cos_ha > 1:
        return "night"
    if cos_ha < -1:
        return "day"
    ha = math.degrees(math.acos(cos_ha))
    return 720 - 4 * (lon + (ha if rising else -ha)) - eqtime


def sun_times(day: date, lat: float, lon: float) -> tuple[datetime, datetime]:
    base = datetime(day.year, day.month, day.day, tzinfo=timezone.utc)
    rise = _utc_minutes(day, lat, lon, True)
    set_ = _utc_minutes(day, lat, lon, False)
    if rise == "day" or set_ == "day":
        return base, base + timedelta(hours=23, minutes=59)
    if isinstance(rise, str) or isinstance(set_, str):
        noon = base + timedelta(hours=12)
        return noon, noon
    return base + timedelta(minutes=rise), base + timedelta(minutes=set_)
