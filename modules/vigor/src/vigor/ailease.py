"""Leases prime-agent keeps fresh while a local-model request runs."""
import os
from pathlib import Path

# prime-agent touches its lease every second; a crashed session stops counting after this.
STALE_S = 5.0


def prepare(lease_dir: Path) -> None:
    lease_dir.mkdir(parents=True, exist_ok=True)
    # mkdir's mode is masked by the umask, so set it explicitly.
    os.chmod(lease_dir, 0o1733)


def active(lease_dir: Path, now: float) -> bool:
    try:
        entries = list(os.scandir(lease_dir))
    except OSError:
        return False
    for e in entries:
        try:
            if e.stat().st_mtime > now - STALE_S:
                return True
        except OSError:
            continue
    return False
