import fcntl
import json
import os
from contextlib import contextmanager
from dataclasses import asdict, dataclass, field
from pathlib import Path

FOREVER = 2.0**53


@dataclass
class State:
    paused_until: float | None = None
    holds: dict[str, float] = field(default_factory=dict)
    last: dict[str, float] = field(default_factory=dict)


def state_dir() -> Path:
    return Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "lumen"


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
