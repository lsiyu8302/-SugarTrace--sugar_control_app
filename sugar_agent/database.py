import sqlite3
from contextlib import contextmanager
from datetime import datetime
from config import DATABASE_PATH


# ── Schema ───────────────────────────────────────────────────────────

DDL = """
CREATE TABLE IF NOT EXISTS food_knowledge (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    name         TEXT    NOT NULL UNIQUE,
    serving_size TEXT,
    sugar_g      REAL    NOT NULL,
    calories     REAL,
    category     TEXT    NOT NULL CHECK(category IN ('奶茶','甜品','糖果','烘焙','水果','其他')),
    source       TEXT,
    created_at   TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S','now'))
);

CREATE TABLE IF NOT EXISTS intake_records (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    food_name    TEXT  NOT NULL,
    serving_size TEXT,
    sugar_g      REAL  NOT NULL,
    calories     REAL,
    category     TEXT  NOT NULL,
    record_time  TEXT  NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S','now')),
    date_key     TEXT  NOT NULL
);

CREATE TABLE IF NOT EXISTS user_settings (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
"""

SEED = """
INSERT OR IGNORE INTO user_settings (key, value) VALUES ('daily_sugar_limit', '50');
"""

_MIGRATIONS: list[str] = []


# ── Connection helper ────────────────────────────────────────────────

@contextmanager
def get_conn():
    conn = sqlite3.connect(DATABASE_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def init_db():
    with get_conn() as conn:
        conn.executescript(DDL)
        conn.executescript(SEED)
        for sql in _MIGRATIONS:
            try:
                conn.execute(sql)
            except sqlite3.OperationalError:
                pass  # column already exists


# ── food_knowledge ───────────────────────────────────────────────────

def upsert_food_knowledge(name, sugar_g, calories, category,
                          serving_size=None, source=None):
    sql = """
        INSERT INTO food_knowledge
            (name, serving_size, sugar_g, calories, category, source)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(name) DO UPDATE SET
            serving_size = excluded.serving_size,
            sugar_g      = excluded.sugar_g,
            calories     = excluded.calories,
            category     = excluded.category,
            source       = excluded.source
    """
    with get_conn() as conn:
        conn.execute(sql, (name, serving_size, sugar_g, calories, category, source))


def fuzzy_search_food_knowledge(name: str) -> dict | None:
    """LIKE search; returns the best (first) match or None."""
    with get_conn() as conn:
        row = conn.execute(
            "SELECT * FROM food_knowledge WHERE name LIKE ? LIMIT 1",
            (f"%{name}%",)
        ).fetchone()
        return dict(row) if row else None


# ── intake_records ───────────────────────────────────────────────────

def insert_intake_record(food_name, sugar_g, calories, category,
                         serving_size=None):
    now = datetime.now()
    date_key = now.strftime("%Y-%m-%d")
    record_time = now.strftime("%Y-%m-%dT%H:%M:%S")
    sql = """
        INSERT INTO intake_records
            (food_name, serving_size, sugar_g, calories,
             category, record_time, date_key)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    """
    with get_conn() as conn:
        cur = conn.execute(sql, (
            food_name, serving_size, sugar_g, calories,
            category, record_time, date_key
        ))
        return cur.lastrowid


def delete_records_by_date(date_key: str) -> int:
    with get_conn() as conn:
        cur = conn.execute("DELETE FROM intake_records WHERE date_key = ?", (date_key,))
        return cur.rowcount


def delete_intake_record(record_id: int) -> bool:
    with get_conn() as conn:
        cur = conn.execute("DELETE FROM intake_records WHERE id = ?", (record_id,))
        return cur.rowcount > 0


def get_records_by_date(date_key: str):
    with get_conn() as conn:
        rows = conn.execute(
            "SELECT * FROM intake_records WHERE date_key = ? ORDER BY record_time",
            (date_key,)
        ).fetchall()
        return [dict(r) for r in rows]


def get_records_by_range(start: str, end: str):
    with get_conn() as conn:
        rows = conn.execute(
            "SELECT * FROM intake_records WHERE date_key BETWEEN ? AND ? ORDER BY record_time",
            (start, end)
        ).fetchall()
        return [dict(r) for r in rows]


def get_daily_total_sugar(date_key: str) -> float:
    with get_conn() as conn:
        row = conn.execute(
            "SELECT COALESCE(SUM(sugar_g), 0) AS total FROM intake_records WHERE date_key = ?",
            (date_key,)
        ).fetchone()
        return float(row["total"])


# ── user_settings ────────────────────────────────────────────────────

def get_all_settings():
    with get_conn() as conn:
        rows = conn.execute("SELECT key, value FROM user_settings").fetchall()
        return {r["key"]: r["value"] for r in rows}


def upsert_setting(key: str, value: str):
    with get_conn() as conn:
        conn.execute(
            "INSERT INTO user_settings (key, value) VALUES (?, ?)"
            " ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            (key, value)
        )
