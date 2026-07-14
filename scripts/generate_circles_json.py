#!/usr/bin/env python3
"""fussa_jinzai.dbから公開可能な地図用circles.jsonを生成する。"""

from __future__ import annotations

import argparse
import json
import sqlite3
from datetime import datetime, timezone
from pathlib import Path


DEFAULT_DB = Path("/home/maji/fussa_jinzai.db")
DEFAULT_OUTPUT = Path(__file__).resolve().parents[1] / "circles.json"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    return parser.parse_args()


def parse_categories(raw: str | None) -> list[str]:
    if not raw:
        return []
    try:
        value = json.loads(raw)
    except json.JSONDecodeError:
        return []
    return [str(item) for item in value] if isinstance(value, list) else []


def generate(db_path: Path) -> dict:
    if not db_path.is_file():
        raise FileNotFoundError(f"DB not found: {db_path}")
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    rows = conn.execute(
        """SELECT c.id, c.source_no, c.name, c.description,
                  c.category_tags_normalized,
                  l.geocoded_lat, l.geocoded_lng,
                  l.needs_verification, l.location_type
           FROM circles c
           JOIN circle_locations l ON l.circle_id = c.id
           WHERE c.is_hidden = 0
             AND l.geocoded_lat IS NOT NULL
             AND l.geocoded_lng IS NOT NULL
           ORDER BY c.source_no"""
    ).fetchall()
    conn.close()

    circles = [{
        "id": row["id"],
        "source_no": row["source_no"],
        "name": row["name"],
        "description": row["description"],
        "categories": parse_categories(row["category_tags_normalized"]),
        "lat": row["geocoded_lat"],
        "lng": row["geocoded_lng"],
        "needs_verification": row["needs_verification"],
        "location_type": row["location_type"],
    } for row in rows]

    verified = sum(circle["needs_verification"] == 0 for circle in circles)
    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "count": len(circles),
        "verified_count": verified,
        "unverified_count": len(circles) - verified,
        "circles": circles,
    }


def main() -> int:
    args = parse_args()
    payload = generate(args.db)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({key: payload[key] for key in ("count", "verified_count", "unverified_count")}, ensure_ascii=False))
    print(f"output={args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
