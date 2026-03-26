#!/usr/bin/env python3
"""Export backend nodes/links API data to APK-bundled SQLite DB.

Usage (from repo root):
  py backend/src/export_sqlite_from_api.py

Options:
  --api-base-url http://localhost:3000
  --output assets/db/nav_database.db
"""

from __future__ import annotations

import argparse
import json
import sqlite3
from pathlib import Path
from urllib.error import URLError, HTTPError
from urllib.request import urlopen


def fetch_json(url: str):
    try:
        with urlopen(url, timeout=20) as response:
            return json.loads(response.read().decode("utf-8"))
    except (HTTPError, URLError, TimeoutError) as exc:
        raise RuntimeError(f"Failed to fetch {url}: {exc}") from exc


def _normalize_nodes(nodes: list[dict]) -> list[tuple[int, str | None, float, float]]:
    normalized: list[tuple[int, str | None, float, float]] = []
    seen_ids: set[int] = set()

    for index, node in enumerate(nodes, start=1):
        try:
            node_id = int(node["id"])
            lat = float(node["latitude"])
            lng = float(node["longitude"])
        except (KeyError, TypeError, ValueError) as exc:
            raise RuntimeError(
                f"Invalid node at index {index}: required fields are id, latitude, longitude"
            ) from exc

        if node_id in seen_ids:
            raise RuntimeError(f"Duplicate node id detected: {node_id}")
        seen_ids.add(node_id)

        raw_name = (
            node.get("name")
            or node.get("node_name")
            or node.get("NODE_NAME")
        )
        name = str(raw_name).strip() if raw_name is not None else None
        if name == "":
            name = None

        normalized.append((node_id, name, lat, lng))

    return normalized


def _normalize_links(links: list[dict], valid_node_ids: set[int]) -> list[tuple[int, int, int, float, str]]:
    normalized: list[tuple[int, int, int, float, str]] = []
    seen_ids: set[int] = set()
    orphan_errors: list[str] = []

    for index, link in enumerate(links, start=1):
        try:
            link_id = int(link["id"])
            start_node = int(link["start_node"])
            end_node = int(link["end_node"])
            weight = float(link["weight"])
        except (KeyError, TypeError, ValueError) as exc:
            raise RuntimeError(
                f"Invalid link at index {index}: required fields are id, start_node, end_node, weight"
            ) from exc

        if link_id in seen_ids:
            raise RuntimeError(f"Duplicate link id detected: {link_id}")
        seen_ids.add(link_id)

        if start_node not in valid_node_ids or end_node not in valid_node_ids:
            orphan_errors.append(
                f"link_id={link_id} start_node={start_node} end_node={end_node}"
            )

        road_name = str(link.get("road_name") or "도로")
        normalized.append((link_id, start_node, end_node, weight, road_name))

    if orphan_errors:
        sample = "\n".join(orphan_errors[:20])
        extra = ""
        if len(orphan_errors) > 20:
            extra = f"\n... and {len(orphan_errors) - 20} more"
        raise RuntimeError(
            "Found links that reference missing node ids:\n"
            f"{sample}{extra}"
        )

    return normalized


def _normalize_turninfos(
    turninfos: list[dict], valid_link_ids: set[int]
) -> list[tuple[int | None, int, int, str, str | None]]:
    normalized: list[tuple[int | None, int, int, str, str | None]] = []
    seen_pairs: set[tuple[int, int]] = set()

    for index, item in enumerate(turninfos, start=1):
        try:
            prev_link_id = int(item["prev_link_id"])
            next_link_id = int(item["next_link_id"])
            turn_type = str(item["turn_type"]).strip()
        except (KeyError, TypeError, ValueError) as exc:
            raise RuntimeError(
                f"Invalid turninfo at index {index}: required fields are prev_link_id, next_link_id, turn_type"
            ) from exc

        if prev_link_id not in valid_link_ids or next_link_id not in valid_link_ids:
            continue

        pair = (prev_link_id, next_link_id)
        if pair in seen_pairs:
            continue
        seen_pairs.add(pair)

        raw_id = item.get("id")
        row_id = int(raw_id) if raw_id is not None else None
        raw_desc = item.get("turn_desc") or item.get("description")
        description = str(raw_desc).strip() if raw_desc is not None else None
        if description == "":
            description = None

        normalized.append(
            (row_id, prev_link_id, next_link_id, turn_type, description)
        )

    return normalized


def _seed_turn_type_dictionary(conn: sqlite3.Connection) -> None:
    turn_type_codes = [
        ("001", "비보호회전"),
        ("002", "버스만회전"),
        ("003", "회전금지"),
        ("011", "U-TURN"),
        ("012", "P-TURN"),
        ("101", "좌회전금지"),
        ("102", "직진금지"),
        ("103", "우회전금지"),
    ]

    for turn_type, turn_desc in turn_type_codes:
        conn.execute(
            """
            INSERT INTO TB_TURNINFO (PREV_LINK_ID, NEXT_LINK_ID, TURN_TYPE, TURN_DESC)
            SELECT NULL, NULL, ?, ?
            WHERE NOT EXISTS (
              SELECT 1 FROM TB_TURNINFO
              WHERE PREV_LINK_ID IS NULL
                AND NEXT_LINK_ID IS NULL
                AND TURN_TYPE = ?
            )
            """,
            (turn_type, turn_desc, turn_type),
        )


def build_sqlite(
    db_path: Path,
    node_rows: list[tuple[int, str | None, float, float]],
    link_rows: list[tuple[int, int, int, float, str]],
    turninfo_rows: list[tuple[int | None, int, int, str, str | None]],
) -> None:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    if db_path.exists():
        db_path.unlink()

    conn = sqlite3.connect(str(db_path))
    try:
        conn.execute("PRAGMA foreign_keys = ON")

        conn.execute(
            """
            CREATE TABLE nodes (
              id INTEGER PRIMARY KEY,
                            name TEXT,
              latitude REAL NOT NULL,
              longitude REAL NOT NULL
            )
            """
        )

        conn.execute(
            """
            CREATE TABLE links (
              id INTEGER PRIMARY KEY,
              start_node INTEGER NOT NULL,
              end_node INTEGER NOT NULL,
              weight REAL NOT NULL,
              road_name TEXT NOT NULL,
              FOREIGN KEY(start_node) REFERENCES nodes(id),
              FOREIGN KEY(end_node) REFERENCES nodes(id)
            )
            """
        )

        conn.execute(
            """
            CREATE TABLE TB_TURNINFO (
              ID INTEGER PRIMARY KEY AUTOINCREMENT,
              PREV_LINK_ID INTEGER,
              NEXT_LINK_ID INTEGER,
              TURN_TYPE TEXT NOT NULL,
              TURN_DESC TEXT,
              FOREIGN KEY(PREV_LINK_ID) REFERENCES links(id) ON DELETE RESTRICT,
              FOREIGN KEY(NEXT_LINK_ID) REFERENCES links(id) ON DELETE RESTRICT
            )
            """
        )

        conn.executemany(
            "INSERT INTO nodes (id, name, latitude, longitude) VALUES (?, ?, ?, ?)",
            node_rows,
        )

        conn.executemany(
            "INSERT INTO links (id, start_node, end_node, weight, road_name) VALUES (?, ?, ?, ?, ?)",
            link_rows,
        )

        conn.executemany(
            """
            INSERT INTO TB_TURNINFO (ID, PREV_LINK_ID, NEXT_LINK_ID, TURN_TYPE, TURN_DESC)
            VALUES (?, ?, ?, ?, ?)
            """,
            turninfo_rows,
        )

        conn.execute("CREATE INDEX idx_links_start_node ON links(start_node)")
        conn.execute("CREATE INDEX idx_links_end_node ON links(end_node)")
        conn.execute("CREATE INDEX idx_nodes_name ON nodes(name)")
        conn.execute(
            "CREATE INDEX idx_turninfo_prev_next ON TB_TURNINFO(PREV_LINK_ID, NEXT_LINK_ID)"
        )
        conn.execute("CREATE INDEX idx_turninfo_type ON TB_TURNINFO(TURN_TYPE)")
        conn.execute(
            """
            CREATE UNIQUE INDEX uq_turninfo_transition
            ON TB_TURNINFO(PREV_LINK_ID, NEXT_LINK_ID)
            WHERE PREV_LINK_ID IS NOT NULL AND NEXT_LINK_ID IS NOT NULL
            """
        )

        _seed_turn_type_dictionary(conn)

        # user_version=6: 최신 Node/Link/TurnInfo 번들 데이터 반영 버전
        conn.execute("PRAGMA user_version = 6")
        # WAL 파일 없이 단일 파일로 배포 가능하게 journal_mode=DELETE 설정
        conn.execute("PRAGMA journal_mode = DELETE")

        conn.commit()
    finally:
        conn.close()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Export backend nodes/links to assets/db/nav_database.db"
    )
    parser.add_argument(
        "--api-base-url",
        default="http://localhost:3000",
        help="Backend API base URL (default: http://localhost:3000)",
    )
    parser.add_argument(
        "--output",
        default="assets/db/nav_database.db",
        help="Output SQLite DB path relative to repo root",
    )
    args = parser.parse_args()

    api = args.api_base_url.rstrip("/")
    nodes_url = f"{api}/api/nodes"
    links_url = f"{api}/api/links"
    turninfos_url = f"{api}/api/turninfos"

    nodes = fetch_json(nodes_url)
    links = fetch_json(links_url)
    turninfos = fetch_json(turninfos_url)

    if (
        not isinstance(nodes, list)
        or not isinstance(links, list)
        or not isinstance(turninfos, list)
    ):
        raise RuntimeError("Unexpected API response format")

    root_dir = Path(__file__).resolve().parents[2]
    output_path = root_dir / args.output

    node_rows = _normalize_nodes(nodes)
    valid_node_ids = {node_id for (node_id, _, _, _) in node_rows}
    link_rows = _normalize_links(links, valid_node_ids)
    valid_link_ids = {link_id for (link_id, _, _, _, _) in link_rows}
    turninfo_rows = _normalize_turninfos(turninfos, valid_link_ids)

    build_sqlite(output_path, node_rows, link_rows, turninfo_rows)

    print(f"sqlite_export_ok: {output_path}")
    print(f"nodes: {len(node_rows)}")
    print(f"links: {len(link_rows)}")
    print(f"turninfos: {len(turninfo_rows)}")
    print("integrity_check: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
