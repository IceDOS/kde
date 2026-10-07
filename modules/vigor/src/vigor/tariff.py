"""Price per kWh at a given local time, with time-of-use bands, surcharge and VAT."""
from datetime import datetime, time

from .config import Config


def _hm(s: str) -> time:
    h, m = s.split(":")
    return time(int(h), int(m))


def _in_band(t: time, start: time, end: time) -> bool:
    return start <= t < end if start < end else (t >= start or t < end)


def unit_price(cfg: Config, when: datetime) -> float:
    base = cfg.price
    t = when.time()
    for b in cfg.bands:
        if _in_band(t, _hm(b.start), _hm(b.end)):
            base = b.price
            break
    return (base + cfg.surcharge) * (1 + cfg.vat / 100)


def cost(cfg: Config, wh: float, when: datetime) -> float:
    return wh / 1000 * unit_price(cfg, when)
