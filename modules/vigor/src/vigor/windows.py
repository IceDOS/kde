"""Window labels shared with prime-agent's cost footer: "15m", "24h", "2w", "1M" (calendar months)."""
import calendar
import re
from datetime import datetime

UNIT_S = {"s": 1, "m": 60, "h": 3600, "d": 86400, "w": 7 * 86400, "M": 31 * 86400}


def parse(label: str) -> tuple[int, int]:
    m = re.fullmatch(r"([1-9][0-9]*)([smhdwM])", label)
    if not m:
        raise ValueError(f"bad window label: {label!r}")
    n, unit = int(m.group(1)), m.group(2)
    return n * UNIT_S[unit], n if unit == "M" else 0


def months_ago(now: datetime, n: int) -> datetime:
    y, mo = divmod(now.year * 12 + now.month - 1 - n, 12)
    # Mar 31 minus one month is the end of February, not Mar 3.
    day = min(now.day, calendar.monthrange(y, mo + 1)[1])
    return now.replace(year=y, month=mo + 1, day=day)


def start(label: str, now: datetime) -> datetime:
    span, months = parse(label)
    return months_ago(now, months) if months else datetime.fromtimestamp(now.timestamp() - span)
