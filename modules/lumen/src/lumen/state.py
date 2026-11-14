import fcntl
import json
import os
import sys
from contextlib import contextmanager
from dataclasses import asdict, dataclass, field
from pathlib import Path

FOREVER = 2.0**53
_warned_dirs: set[Path] = set()


@dataclass
class State:
    paused_until: float | None = None
    holds: dict[str, float] = field(default_factory=dict)
    last: dict[str, float] = field(default_factory=dict)


def _migrate() -> None:
    base = Path(os.environ.get("XDG_STATE_HOME") or (Path.home() / ".local/state"))
    new_dir = base / "icedos" / "lumen"
    legacy_dir = base / "lumen"  # legacy path pre-2026-11
    if not new_dir.exists() and legacy_dir.exists():
        new_dir.parent.mkdir(parents=True, exist_ok=True)
        try:
            legacy_dir.rename(new_dir)
        except OSError:
            pass
    elif new_dir.exists() and legacy_dir.exists():
        for f in legacy_dir.iterdir():
            if f.name == "lock" or not f.is_file():
                if f.name == "lock":
                    try:
                        f.unlink()
                    except OSError:
                        pass
                continue
            target = new_dir / f.name
            try:
                if not target.exists() or f.stat().st_mtime > target.stat().st_mtime:
                    f.replace(target)
                else:
                    f.unlink()
            except OSError:
                pass
        try:
            legacy_dir.rmdir()
        except OSError:
            pass


def state_dir() -> Path:
    _migrate()
    base = Path(os.environ.get("XDG_STATE_HOME") or (Path.home() / ".local/state"))
    return base / "icedos" / "lumen"


def runtime_dir() -> Path:
    return Path(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}") / "lumen"


def write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data))
    os.replace(tmp, path)


@contextmanager
def locked(dir_: Path):
    dir_.mkdir(parents=True, exist_ok=True)
    path = dir_ / "state.json"
    with open(dir_ / "lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            st = State(**json.loads(path.read_text()))
        except (OSError, ValueError, TypeError):
            st = State()
        yield st, lambda: write_json(path, asdict(st))
