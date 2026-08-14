#!/usr/bin/env python3
"""Query the SQLite index for transaction/workflow mappings."""

from __future__ import annotations

import argparse
import json
import sqlite3
from pathlib import Path
from typing import Any


def fetch_all(conn: sqlite3.Connection, sql: str, params: tuple[Any, ...]) -> list[dict[str, Any]]:
    conn.row_factory = sqlite3.Row
    return [dict(row) for row in conn.execute(sql, params).fetchall()]


def like(term: str) -> str:
    return f"%{term}%"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("sqlite_db", type=Path)
    parser.add_argument("--request-number")
    parser.add_argument("--transaction-name")
    parser.add_argument("--script-name")
    parser.add_argument("--service-binding")
    parser.add_argument("--server-name")
    parser.add_argument("--workflow-name")
    parser.add_argument("--limit", type=int, default=25)
    args = parser.parse_args()

    limit = max(1, min(args.limit, 100))
    response: dict[str, Any] = {}

    with sqlite3.connect(args.sqlite_db) as conn:
        if args.request_number:
            response["prg_metadata"] = fetch_all(
                conn,
                """
                SELECT *
                FROM prg_metadata
                WHERE LOWER(request_number) = LOWER(?)
                ORDER BY script_name, file_path
                LIMIT ?
                """,
                (args.request_number, limit),
            )
            response["tdb_metadata"] = fetch_all(
                conn,
                """
                SELECT *
                FROM tdb_metadata
                WHERE LOWER(request_number) = LOWER(?)
                ORDER BY request_name
                LIMIT ?
                """,
                (args.request_number, limit),
            )
            response["workflow_records"] = fetch_all(
                conn,
                """
                SELECT *
                FROM workflow_records
                WHERE LOWER(request_number) = LOWER(?)
                ORDER BY workflow_name, yaml_path
                LIMIT ?
                """,
                (args.request_number, limit),
            )

        if args.transaction_name:
            response["transaction_matches"] = fetch_all(
                conn,
                """
                SELECT *
                FROM tdb_metadata
                WHERE LOWER(request_name) LIKE LOWER(?)
                ORDER BY request_number, request_name
                LIMIT ?
                """,
                (like(args.transaction_name), limit),
            )
            response["workflow_transaction_matches"] = fetch_all(
                conn,
                """
                SELECT *
                FROM workflow_records
                WHERE LOWER(transaction_name) LIKE LOWER(?)
                ORDER BY workflow_name, yaml_path
                LIMIT ?
                """,
                (like(args.transaction_name), limit),
            )

        if args.script_name:
            response["script_matches"] = fetch_all(
                conn,
                """
                SELECT *
                FROM prg_metadata
                WHERE LOWER(script_name) LIKE LOWER(?)
                ORDER BY request_number, script_name
                LIMIT ?
                """,
                (like(args.script_name), limit),
            )
            response["workflow_script_matches"] = fetch_all(
                conn,
                """
                SELECT *
                FROM workflow_records
                WHERE LOWER(script_name) LIKE LOWER(?)
                ORDER BY workflow_name, yaml_path
                LIMIT ?
                """,
                (like(args.script_name), limit),
            )

        if args.service_binding:
            response["binding_transaction_matches"] = fetch_all(
                conn,
                """
                SELECT *
                FROM tdb_metadata
                WHERE LOWER(service_binding) LIKE LOWER(?)
                ORDER BY request_number, request_name
                LIMIT ?
                """,
                (like(args.service_binding), limit),
            )
            response["binding_server_matches"] = fetch_all(
                conn,
                """
                SELECT *
                FROM scp_definitions
                WHERE LOWER(service_binding) LIKE LOWER(?)
                ORDER BY scp_number, server_name
                LIMIT ?
                """,
                (like(args.service_binding), limit),
            )
            response["workflow_binding_matches"] = fetch_all(
                conn,
                """
                SELECT *
                FROM workflow_records
                WHERE LOWER(service_binding) LIKE LOWER(?)
                ORDER BY workflow_name, yaml_path
                LIMIT ?
                """,
                (like(args.service_binding), limit),
            )

        if args.server_name:
            response["server_matches"] = fetch_all(
                conn,
                """
                SELECT *
                FROM scp_definitions
                WHERE LOWER(server_name) LIKE LOWER(?)
                ORDER BY scp_number, server_name
                LIMIT ?
                """,
                (like(args.server_name), limit),
            )
            response["workflow_server_matches"] = fetch_all(
                conn,
                """
                SELECT *
                FROM workflow_records
                WHERE LOWER(server_name) LIKE LOWER(?)
                ORDER BY workflow_name, yaml_path
                LIMIT ?
                """,
                (like(args.server_name), limit),
            )

        if args.workflow_name:
            response["workflow_records"] = fetch_all(
                conn,
                """
                SELECT *
                FROM workflow_records
                WHERE LOWER(workflow_name) LIKE LOWER(?)
                ORDER BY workflow_name, yaml_path
                LIMIT ?
                """,
                (like(args.workflow_name), limit),
            )

    print(json.dumps(response, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
