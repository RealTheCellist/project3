from __future__ import annotations

import json
import sqlite3
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Dict, Iterator, List


DB_PATH = Path("data/sumpyo.db")


def get_conn() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


@contextmanager
def open_conn() -> Iterator[sqlite3.Connection]:
    conn = get_conn()
    try:
        yield conn
    finally:
        conn.close()


def init_db() -> None:
    with open_conn() as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS checkins (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                transcript TEXT NOT NULL,
                recovery_score INTEGER NOT NULL,
                risk_score INTEGER NOT NULL,
                confidence REAL NOT NULL,
                hold_decision INTEGER NOT NULL,
                tags_json TEXT NOT NULL,
                explanation TEXT NOT NULL
            )
            """
        )
        conn.commit()


def insert_checkin(transcript: str, result: Dict[str, Any]) -> int:
    tags_json = json.dumps(result.get("tags", []), ensure_ascii=False)
    with open_conn() as conn:
        cur = conn.execute(
            """
            INSERT INTO checkins (
                transcript, recovery_score, risk_score, confidence,
                hold_decision, tags_json, explanation
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                transcript,
                int(result["recovery_score"]),
                int(result["risk_score"]),
                float(result["confidence"]),
                1 if bool(result["hold_decision"]) else 0,
                tags_json,
                str(result["explanation"]),
            ),
        )
        conn.commit()
        return int(cur.lastrowid)


def list_checkins(limit: int = 20) -> List[Dict[str, Any]]:
    safe_limit = max(1, min(limit, 100))
    with open_conn() as conn:
        rows = conn.execute(
            """
            SELECT id, created_at, transcript, recovery_score, risk_score,
                   confidence, hold_decision, tags_json, explanation
            FROM checkins
            ORDER BY id DESC
            LIMIT ?
            """,
            (safe_limit,),
        ).fetchall()

    results: List[Dict[str, Any]] = []
    for row in rows:
        tags = json.loads(row["tags_json"]) if row["tags_json"] else []
        results.append(
            {
                "id": int(row["id"]),
                "created_at": str(row["created_at"]),
                "transcript": str(row["transcript"]),
                "recovery_score": int(row["recovery_score"]),
                "risk_score": int(row["risk_score"]),
                "confidence": float(row["confidence"]),
                "hold_decision": bool(row["hold_decision"]),
                "tags": tags,
                "explanation": str(row["explanation"]),
            }
        )
    return results
