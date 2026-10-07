from datetime import datetime

import pytest

from vigor import tariff
from vigor.config import Band, Config

CFG = Config(price=0.10, surcharge=0.02, vat=6, bands=(Band("23:00", "07:00", 0.05),))


def test_day_price_includes_surcharge_and_vat():
    assert tariff.unit_price(CFG, datetime(2026, 10, 7, 12, 0)) == pytest.approx(0.12 * 1.06)


@pytest.mark.parametrize("h", [23, 2, 6])
def test_band_across_midnight(h):
    assert tariff.unit_price(CFG, datetime(2026, 10, 7, h, 30)) == pytest.approx(0.07 * 1.06)


def test_band_end_is_exclusive():
    assert tariff.unit_price(CFG, datetime(2026, 10, 7, 7, 0)) == pytest.approx(0.12 * 1.06)


def test_cost_of_one_kwh():
    assert tariff.cost(CFG, 1000.0, datetime(2026, 10, 7, 12, 0)) == pytest.approx(0.1272)
