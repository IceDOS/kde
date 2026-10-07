from collections.abc import Callable
from datetime import datetime

from lumen.config import Config, Monitor, to_edit_dict
from lumen.curve import SunFn, next_point, sample_day, value_at
from lumen.display import Display
from lumen.state import State


def _clamp(cfg: Config, v: float) -> float:
    return round(max(cfg.min_brightness, min(100.0, v)), 1)


def target_for(cfg: Config, mon: Monitor, now: datetime, sun: SunFn) -> float | None:
    if not mon.enable:
        return None
    return _clamp(cfg, value_at(mon.points or cfg.points, now, sun) * mon.scale + mon.offset)


def hold(cfg: Config, st: State, label: str, now: datetime, sun: SunFn) -> None:
    st.holds[label] = next_point(cfg.monitor(label).points or cfg.points, now, sun).timestamp()


def _hm(dt: datetime, now: datetime) -> str:
    return dt.astimezone(now.tzinfo).strftime("%H:%M")


def tick(
    cfg: Config,
    st: State,
    displays: list[Display],
    now: datetime,
    sun: SunFn,
    setter: Callable[[str, int], None],
    edited: bool = False,
) -> dict:
    ts = now.timestamp()
    if st.paused_until is not None and st.paused_until <= ts:
        st.paused_until = None
    paused = st.paused_until is not None

    rows = []
    for d in displays:
        mon = cfg.monitor(d.label)
        target = target_for(cfg, mon, now, sun)
        last = st.last.get(d.label)
        current, error = round(d.pct, 1), ""
        # An asleep panel keeps a stale reading, so it is neither a manual change nor a target to write.
        if d.awake:
            if last is not None and target is not None and abs(d.pct - last) > cfg.tolerance:
                hold(cfg, st, d.label, now, sun)
                st.last[d.label] = d.pct
            if st.holds.get(d.label, ts + 1) <= ts:
                del st.holds[d.label]

            if target is not None and not paused and d.label not in st.holds and abs(d.pct - target) >= 0.5:
                try:
                    setter(d.bus, round(target * d.max / 100))
                    current = st.last[d.label] = target
                except Exception as e:  # DDC errors must not stop the other monitors
                    error = str(e)
            elif last is None or target is None:
                st.last[d.label] = d.pct

        pts = mon.points or cfg.points
        rows.append(
            {
                "bus": d.bus,
                "label": d.label,
                "awake": d.awake,
                "current": current,
                "target": target,
                "held_until": st.holds.get(d.label),
                "enable": mon.enable,
                "scale": mon.scale,
                "offset": mon.offset,
                "custom": bool(mon.points),
                "curve": [_clamp(cfg, v * mon.scale + mon.offset) for v in sample_day(pts, now, sun)],
                "error": error,
            }
        )

    rise, set_ = sun(now.date())
    nxt = next_point(cfg.points, now, sun)
    return {
        "ts": ts,
        "interval": cfg.interval,
        "paused_until": st.paused_until,
        "sunrise": _hm(rise, now),
        "sunset": _hm(set_, now),
        "next": {"at": _hm(nxt, now), "brightness": round(value_at(cfg.points, nxt, sun))},
        "edited": edited,
        "config": to_edit_dict(cfg),
        "monitors": rows,
    }
