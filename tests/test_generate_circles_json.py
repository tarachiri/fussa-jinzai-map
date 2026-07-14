import importlib.util
import json
import sqlite3
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[1] / "scripts" / "generate_circles_json.py"
SPEC = importlib.util.spec_from_file_location("generate_circles_json", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(MODULE)


class GenerateCirclesJsonTest(unittest.TestCase):
    def make_db(self):
        temp = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
        temp.close()
        path = Path(temp.name)
        conn = sqlite3.connect(path)
        conn.executescript("""
            CREATE TABLE circles (
              id INTEGER PRIMARY KEY, source_no TEXT, name TEXT, description TEXT,
              category_tags_normalized TEXT, is_hidden INTEGER,
              representative_name TEXT, contact_disclosure_status TEXT
            );
            CREATE TABLE circle_locations (
              id INTEGER PRIMARY KEY, circle_id INTEGER, geocoded_lat REAL,
              geocoded_lng REAL, needs_verification INTEGER, location_type TEXT
            );
        """)
        return path, conn

    def test_generate_filters_hidden_and_null_coordinates(self):
        path, conn = self.make_db()
        conn.executemany(
            "INSERT INTO circles VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            [
                (1, "001", "公開団体", "活動内容", '["社会教育"]', 0, "非公開代表", "unconfirmed"),
                (2, "002", "非表示団体", "説明", "[]", 1, "非公開代表", "unconfirmed"),
                (3, "003", "座標なし", "説明", "[]", 0, "非公開代表", "unconfirmed"),
            ],
        )
        conn.executemany(
            "INSERT INTO circle_locations VALUES (?, ?, ?, ?, ?, ?)",
            [(1, 1, 35.7, 139.3, 0, "address"), (2, 2, 35.7, 139.3, 1, "address"), (3, 3, None, None, 1, "none")],
        )
        conn.commit()
        conn.close()
        payload = MODULE.generate(path)
        self.assertEqual(payload["count"], 1)
        self.assertEqual(payload["circles"][0]["name"], "公開団体")
        serialized = json.dumps(payload, ensure_ascii=False)
        self.assertNotIn("非公開代表", serialized)
        self.assertNotIn("contact_disclosure_status", serialized)
        path.unlink()

    def test_invalid_categories_are_empty(self):
        self.assertEqual(MODULE.parse_categories("not-json"), [])
        self.assertEqual(MODULE.parse_categories('{"x": 1}'), [])


if __name__ == "__main__":
    unittest.main()
