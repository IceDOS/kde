"""Per-minute energy and cost buckets per component, plus a small key/value meta table."""
import sqlite3
from pathlib import Path

SCHEMA = """
CREATE TABLE IF NOT EXISTS energy (
  minute    INTEGER NOT NULL,  -- unix time // 60
  component TEXT    NOT NULL,
  wh        REAL    NOT NULL,
  cost      REAL    NOT NULL,
  PRIMARY KEY (minute, component)
);
CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v TEXT);
"""
# Rows that measure a share of another row; summing them would count that energy twice.
PART_OF_GPU = ("ai",)


def connect(path: Path) -> sqlite3.Connection:
    path.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(str(path))
    con.execute("PRAGMA journal_mode=WAL")
    con.executescript(SCHEMA)
    return con


def add(con: sqlite3.Connection, rows: dict) -> None:
    con.executemany(
        "INSERT INTO energy VALUES (?,?,?,?) ON CONFLICT(minute, component) "
        "DO UPDATE SET wh = wh + excluded.wh, cost = cost + excluded.cost",
        [(m, c, wh, cost) for (m, c), (wh, cost) in rows.items()],
    )
    con.commit()


def totals(con: sqlite3.Connection, since_minute: int) -> dict:
    by = {
        c: {"wh": wh, "cost": cost}
        for c, wh, cost in con.execute(
            "SELECT component, SUM(wh), SUM(cost) FROM energy WHERE minute >= ? GROUP BY component",
            (since_minute,),
        )
    }
    own = [v for c, v in by.items() if c not in PART_OF_GPU]
    return {"wh": sum(v["wh"] for v in own), "cost": sum(v["cost"] for v in own), "by": by}


def get_meta_float(con: sqlite3.Connection, k: str) -> float | None:
    row = con.execute("SELECT v FROM meta WHERE k=?", (k,)).fetchone()
    return float(row[0]) if row else None


def set_meta(con: sqlite3.Connection, k: str, v) -> None:
    con.execute("INSERT OR REPLACE INTO meta VALUES (?,?)", (k, str(v)))
    con.commit()
