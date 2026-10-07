import argparse
import json
import os
import sys
import time
from datetime import datetime
from functools import partial
from pathlib import Path

from lumen.config import EDIT_KEYS, from_dict, load, minimal_edits
from lumen.curve import next_point
from lumen.display import list_displays, set_brightness
from lumen.engine import hold, tick
from lumen.state import FOREVER, locked, runtime_dir, state_dir, write_json
from lumen.sun import sun_times


def _paths(args) -> tuple[Path, Path]:
    return Path(args.config), state_dir() / "edits.json"


def _cfg(args):
    return load(*_paths(args))


def _sun(cfg):
    return partial(sun_times, lat=cfg.latitude, lon=cfg.longitude)


def _edited(args) -> bool:
    nix_path, edits_path = _paths(args)
    try:
        return bool(minimal_edits(json.loads(nix_path.read_text()), json.loads(edits_path.read_text())))
    except (OSError, ValueError, KeyError, TypeError):
        return False


def _now() -> datetime:
    return datetime.now().astimezone()


def _wake() -> None:
    (state_dir() / "wake").touch()


def cmd_run(args) -> int:
    last_tick, last_wake = 0.0, 0.0
    wake = state_dir() / "wake"
    while True:
        cfg = _cfg(args)
        try:
            mtime = wake.stat().st_mtime
        except FileNotFoundError:
            mtime = 0.0
        if time.time() - last_tick >= cfg.interval or mtime != last_wake:
            last_wake = mtime
            try:
                displays = list_displays()
            except Exception as e:  # ddcutil missing or every display silent
                print(f"lumen: {e}", file=sys.stderr)
                displays = []
            with locked(state_dir()) as (st, save):
                status = tick(cfg, st, displays, _now(), _sun(cfg), set_brightness, _edited(args))
                save()
            write_json(runtime_dir() / "now.json", status)
            last_tick = time.time()
        time.sleep(2)


def cmd_status(args) -> int:
    path = runtime_dir() / "now.json"
    try:
        status = json.loads(path.read_text())
    except (OSError, ValueError):
        status = None
    if not status or time.time() - status["ts"] > 3 * status["interval"]:
        print("lumen service is not running", file=sys.stderr)
        return 1
    if args.json:
        print(json.dumps(status))
        return 0
    for m in status["monitors"]:
        if m.get("awake") is False:
            print(f"{m['label']:<20} asleep")
            continue
        held = f"  manual until {datetime.fromtimestamp(m['held_until']):%H:%M}" if m["held_until"] else ""
        print(f"{m['label']:<20} {m['current']:>5.1f}%  target {m['target'] if m['target'] is not None else 'off'}{held}")
    nxt = status["next"]
    print(f"next {nxt['brightness']}% at {nxt['at']}, sunrise {status['sunrise']}, sunset {status['sunset']}")
    return 0


def cmd_set(args) -> int:
    cfg = _cfg(args)
    now = _now()
    hits = [d for d in list_displays() if args.target in ("all", d.label)]
    if not hits:
        print(f"no display labelled {args.target!r}", file=sys.stderr)
        return 1
    # A sleeping panel ignores writes: skip it under "all", but say so when it was asked for by name.
    asleep = [d.label for d in hits if not d.awake]
    hits = [d for d in hits if d.awake]
    if not hits:
        print(f"asleep: {', '.join(asleep)}", file=sys.stderr)
        return 1
    failed = False
    with locked(state_dir()) as (st, save):
        for d in hits:
            try:
                set_brightness(d.bus, round(args.pct * d.max / 100))
            except Exception as e:  # one failing display must not block the others
                print(f"lumen: {d.label}: {e}", file=sys.stderr)
                failed = True
                continue
            st.last[d.label] = args.pct
            hold(cfg, st, d.label, now, _sun(cfg))
        save()
    if asleep:
        print(f"lumen: skipped asleep: {', '.join(asleep)}", file=sys.stderr)
    _wake()
    return 1 if failed else 0


def cmd_pause(args) -> int:
    cfg = _cfg(args)
    now = _now()
    if args.until == "forever":
        until = FOREVER
    elif args.until == "next":
        until = next_point(cfg.points, now, _sun(cfg)).timestamp()
    else:
        until = now.timestamp() + 60 * int(args.until)
    with locked(state_dir()) as (st, save):
        st.paused_until = until
        save()
    _wake()
    return 0


def cmd_resume(args) -> int:
    with locked(state_dir()) as (st, save):
        if args.label:
            st.holds.pop(args.label, None)
        else:
            st.paused_until = None
            st.holds.clear()
        save()
    _wake()
    return 0


def cmd_edit(args) -> int:
    try:
        nix = json.loads(Path(args.config).read_text())
        edits = {k: v for k, v in json.loads(args.json).items() if k in EDIT_KEYS}
        from_dict({**nix, **edits})
        edits = minimal_edits(nix, edits)
    except (ValueError, KeyError, TypeError) as e:
        print(f"lumen: {e}", file=sys.stderr)
        return 2
    if edits:
        write_json(_paths(args)[1], edits)
    else:
        _paths(args)[1].unlink(missing_ok=True)
    _wake()
    return 0


def cmd_reset(args) -> int:
    _paths(args)[1].unlink(missing_ok=True)
    _wake()
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="lumen", description="Scheduled per-monitor brightness for KDE Plasma.")
    p.add_argument("--config", default=os.environ.get("LUMEN_CONFIG", ""))
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("run").set_defaults(fn=cmd_run)
    s = sub.add_parser("status")
    s.add_argument("--json", action="store_true")
    s.set_defaults(fn=cmd_status)
    s = sub.add_parser("set")
    s.add_argument("target")
    s.add_argument("pct", type=int, choices=range(0, 101), metavar="PCT")
    s.set_defaults(fn=cmd_set)
    s = sub.add_parser("pause")
    s.add_argument("until", nargs="?", default="next")
    s.set_defaults(fn=cmd_pause)
    s = sub.add_parser("resume")
    s.add_argument("label", nargs="?")
    s.set_defaults(fn=cmd_resume)
    s = sub.add_parser("edit")
    s.add_argument("json")
    s.set_defaults(fn=cmd_edit)
    sub.add_parser("reset").set_defaults(fn=cmd_reset)
    args = p.parse_args(argv)
    return args.fn(args)


def entry() -> None:
    sys.exit(main())
