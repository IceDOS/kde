from datetime import datetime

import pytest

from vigor import windows


def test_parse():
    assert windows.parse("15m") == (900, 0)
    assert windows.parse("2w") == (14 * 86400, 0)
    assert windows.parse("1M") == (31 * 86400, 1)


@pytest.mark.parametrize("bad", ["0h", "h", "1y", "1.5h", ""])
def test_parse_rejects(bad):
    with pytest.raises(ValueError):
        windows.parse(bad)


def test_months_ago_clamps_to_month_end():
    assert windows.months_ago(datetime(2026, 3, 31, 12), 1) == datetime(2026, 2, 28, 12)
    assert windows.months_ago(datetime(2026, 1, 15), 1) == datetime(2025, 12, 15)


def test_start():
    now = datetime(2026, 10, 7, 12)
    assert windows.start("24h", now) == datetime(2026, 10, 6, 12)
    assert windows.start("1M", now) == datetime(2026, 9, 7, 12)
