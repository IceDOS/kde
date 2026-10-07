"""Command line: `run` is the service loop, `status` reads its snapshot."""
import argparse
import json
import signal
import sys
import time
from pathlib import Path

from . import ailease, config, store
from .meter import Meter, write_snapshot

# The profile last chosen from the widget, reapplied when the service starts.
TUNE_STATE = config.DB_PATH.parent / "profile"


def format_status(d: dict) -> str:
    cur = d["currency"]
    lines = [f"{d['total_w']:.0f} W  {cur}{d['cost_per_hour']:.4f}/h  ({cur}{d['unit_price']:.3f}/kWh)"]
    for name, w in sorted(d["watts"].items(), key=lambda kv: -kv[1]):
        lines.append(f"  {name:<10}{w:>7.1f} W")
    for t in d["windows"] + [{"label": "all", **d["all"]}]:
        lines.append(f"{t['label']:<6}{t['wh'] / 1000:>8.2f} kWh  {cur}{t['cost']:.2f}")
    ai = d.get("ai")
    if ai and ai["all"]["wh"] > 0:
        lines.append("local AI (part of gpu): " + "  ".join(
            f"{w['label']} {cur}{w['cost']:.2f}" for w in ai["windows"]))
    return "\n".join(lines)


def _status(as_json: bool) -> int:
    try:
        text = config.NOW_PATH.read_text()
    except OSError:
        print(f"vigor service is not running ({config.NOW_PATH} missing)", file=sys.stderr)
        return 1
    print(text if as_json else format_status(json.loads(text)))
    return 0


def _run(cfg: config.Config) -> int:
    ailease.prepare(config.LEASE_DIR)
    meter = Meter(cfg, store.connect(config.DB_PATH),
                  ai_active=lambda: ailease.active(config.LEASE_DIR, time.time()))

    def stop(*_):
        meter.flush(time.time())
        sys.exit(0)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    while True:
        time.sleep(cfg.interval)
        snap = meter.tick()
        if snap is not None:
            write_snapshot(config.NOW_PATH, snap)


def _tune(args) -> int:
    from . import tune
    root = Path("/")
    if args.action == "restore":
        tune.restore(root, TUNE_STATE)
        return 0
    if args.profile not in tune.PROFILES:
        print(f"profile must be one of {', '.join(tune.PROFILES)}", file=sys.stderr)
        return 2
    tune.apply(root, args.profile)
    tune.save(TUNE_STATE, args.profile)
    return 0


def _ctl(args) -> int:
    from . import desk
    root = Path("/")
    if args.action == "status":
        print(json.dumps(desk.status(root)))
        return 0
    if args.action == "profile":
        return desk.set_profile(root, args.arg)
    if args.action in ("hold", "release"):
        return desk.start_hold(args.arg, args.minutes) if args.action == "hold" else desk.stop_hold(args.arg)
    if args.action in ("allow", "block"):
        return desk.allow(args.arg, args.why, args.action == "allow")
    if args.action == "firmware":
        return desk.firmware_reboot()
    return 2


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="vigor")
    ap.add_argument("--config", type=Path)
    sub = ap.add_subparsers(dest="cmd")
    sub.add_parser("run", help="sample forever (the system service)")
    st = sub.add_parser("status", help="print the latest snapshot")
    st.add_argument("--json", action="store_true")
    tu = sub.add_parser("tune", help="set CPU governor and boost for a power profile (root)")
    tu.add_argument("action", choices=["apply", "restore"])
    tu.add_argument("profile", nargs="?", default="")
    ct = sub.add_parser("ctl", help="widget controls: status, profile, hold, release, allow, block, firmware")
    ct.add_argument("action", choices=["status", "profile", "hold", "release", "allow", "block", "firmware"])
    ct.add_argument("arg", nargs="?", default="")
    ct.add_argument("--minutes", type=int, default=0)
    ct.add_argument("--why", default="")
    ho = sub.add_parser("hold", help="hold one inhibition until killed (run by ctl hold)")
    ho.add_argument("kind")
    args = ap.parse_args(argv)
    if args.cmd == "run":
        return _run(config.load(args.config))
    if args.cmd == "tune":
        return _tune(args)
    if args.cmd == "ctl":
        return _ctl(args)
    if args.cmd == "hold":
        from . import desk
        return desk.hold(args.kind)
    return _status(getattr(args, "json", False))
