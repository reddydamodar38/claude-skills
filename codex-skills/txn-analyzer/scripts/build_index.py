#!/usr/bin/env python3
"""Build a SQLite index from transaction, server, and workflow flat files."""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import sqlite3
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

try:
    import yaml
except ImportError as exc:  # pragma: no cover
    raise SystemExit("PyYAML is required to run this script.") from exc

MISSING_VALUES = {"", "tba", "tbd", "na", "n/a", "null", "none"}
FIELD_ALIASES = {
    "workflow_name": {"workflow", "workflowname", "scenario", "scenarioname", "name", "title"},
    "step_name": {"step", "stepname", "action", "name"},
    "request_number": {"requestnumber", "request_number", "requestid", "requestidnumber", "req", "request"},
    "transaction_name": {"transactionname", "transaction_name", "requestname", "request", "transaction"},
    "script_name": {"scriptname", "script_name", "script", "file", "filename"},
    "service_binding": {"servicebinding", "service_binding", "binding", "serverbinding"},
    "server_name": {"servername", "server_name", "server"},
    "service_name": {"service", "servicename"},
}


@dataclass
class Record:
    workflow_file: str
    workflow_name: str | None = None
    yaml_path: str | None = None
    field_name: str | None = None
    field_value: str | None = None
    request_number: str | None = None
    transaction_name: str | None = None
    script_name: str | None = None
    service_binding: str | None = None
    server_name: str | None = None
    step_name: str | None = None
    raw_context: str | None = None


def normalize(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    if not text:
        return None
    if text.lower() in MISSING_VALUES:
        return None
    return text


def norm_key(value: Any) -> str:
    return re.sub(r"[^a-z0-9]+", "", str(value).strip().lower())


def find_files(root: Path, filename: str) -> list[Path]:
    return sorted(root.rglob(filename))


def load_csv_rows(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as fh:
        reader = csv.DictReader(fh)
        return list(reader)


def extract_scalar_records(obj: Any, file_path: str, yaml_path: str = "$") -> list[Record]:
    records: list[Record] = []

    def walk(node: Any, path: str, inherited: dict[str, str | None]) -> None:
        if isinstance(node, dict):
            lower_map = {norm_key(k): k for k in node.keys()}
            current = dict(inherited)
            for target, aliases in FIELD_ALIASES.items():
                if current.get(target):
                    continue
                for alias in aliases:
                    if alias in lower_map:
                        current[target] = normalize(node[lower_map[alias]])
                        break
            workflow_name = current.get("workflow_name")
            if workflow_name and any(current.get(k) for k in ("request_number", "transaction_name", "script_name", "service_binding", "server_name", "step_name")):
                records.append(
                    Record(
                        workflow_file=file_path,
                        workflow_name=workflow_name,
                        yaml_path=path,
                        field_name="dict",
                        field_value=None,
                        request_number=current.get("request_number"),
                        transaction_name=current.get("transaction_name"),
                        script_name=current.get("script_name"),
                        service_binding=current.get("service_binding"),
                        server_name=current.get("server_name"),
                        step_name=current.get("step_name"),
                        raw_context=json.dumps(node, ensure_ascii=False, default=str),
                    )
                )
            for key, value in node.items():
                child_path = f"{path}.{key}" if path != "$" else f"$.{key}"
                if isinstance(value, (dict, list)):
                    walk(value, child_path, current)
                else:
                    val = normalize(value)
                    if val is not None:
                        records.append(
                            Record(
                                workflow_file=file_path,
                                workflow_name=current.get("workflow_name"),
                                yaml_path=child_path,
                                field_name=str(key),
                                field_value=val,
                                request_number=current.get("request_number") or (val if norm_key(key) in FIELD_ALIASES["request_number"] else None),
                                transaction_name=current.get("transaction_name"),
                                script_name=current.get("script_name"),
                                service_binding=current.get("service_binding"),
                                server_name=current.get("server_name"),
                                step_name=current.get("step_name") or (val if norm_key(key) in FIELD_ALIASES["step_name"] else None),
                                raw_context=json.dumps({key: value}, ensure_ascii=False, default=str),
                            )
                        )
        elif isinstance(node, list):
            for idx, item in enumerate(node):
                walk(item, f"{path}[{idx}]", inherited)
        else:
            val = normalize(node)
            if val is not None:
                records.append(
                    Record(
                        workflow_file=file_path,
                        yaml_path=path,
                        field_name="scalar",
                        field_value=val,
                        raw_context=json.dumps(node, ensure_ascii=False, default=str),
                    )
                )

    walk(obj, yaml_path, {})
    return records


def create_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        PRAGMA journal_mode=WAL;

        CREATE TABLE IF NOT EXISTS prg_metadata (
            file_path TEXT,
            script_name TEXT,
            request_number TEXT,
            product TEXT,
            normalized_request_number TEXT
        );

        CREATE TABLE IF NOT EXISTS tdb_metadata (
            request_number TEXT,
            request_name TEXT,
            request_type TEXT,
            service_binding TEXT,
            normalized_request_number TEXT,
            normalized_service_binding TEXT
        );

        CREATE TABLE IF NOT EXISTS scp_definitions (
            scp_number TEXT,
            server_name TEXT,
            service TEXT,
            service_binding TEXT,
            normalized_service_binding TEXT
        );

        CREATE TABLE IF NOT EXISTS workflow_records (
            workflow_file TEXT,
            workflow_name TEXT,
            yaml_path TEXT,
            field_name TEXT,
            field_value TEXT,
            request_number TEXT,
            transaction_name TEXT,
            script_name TEXT,
            service_binding TEXT,
            server_name TEXT,
            step_name TEXT,
            raw_context TEXT
        );

        CREATE TABLE IF NOT EXISTS metadata (
            key TEXT PRIMARY KEY,
            value TEXT
        );
        """
    )


def write_index(conn: sqlite3.Connection, input_dir: Path) -> None:
    cur = conn.cursor()
    cur.execute("DELETE FROM prg_metadata")
    cur.execute("DELETE FROM tdb_metadata")
    cur.execute("DELETE FROM scp_definitions")
    cur.execute("DELETE FROM workflow_records")

    prg_csv = input_dir / "prg_metadata.csv"
    if prg_csv.exists():
        for row in load_csv_rows(prg_csv):
            request_number = normalize(row.get("RequestNumber"))
            cur.execute(
                "INSERT INTO prg_metadata VALUES (?, ?, ?, ?, ?)",
                (
                    normalize(row.get("File")),
                    normalize(row.get("ScriptName")),
                    request_number,
                    normalize(row.get("Product")),
                    request_number.lower() if request_number else None,
                ),
            )

    tdb_csv = input_dir / "tdb_metadata.csv"
    if tdb_csv.exists():
        for row in load_csv_rows(tdb_csv):
            request_number = normalize(row.get("RequestNumber"))
            binding = normalize(row.get("ServiceBinding"))
            cur.execute(
                "INSERT INTO tdb_metadata VALUES (?, ?, ?, ?, ?, ?)",
                (
                    request_number,
                    normalize(row.get("RequestName")),
                    normalize(row.get("RequestType")),
                    binding,
                    request_number.lower() if request_number else None,
                    binding.lower() if binding else None,
                ),
            )

    scp_csv = input_dir / "scp_definitions.csv"
    if scp_csv.exists():
        for row in load_csv_rows(scp_csv):
            binding = normalize(row.get("ServiceBinding"))
            cur.execute(
                "INSERT INTO scp_definitions VALUES (?, ?, ?, ?, ?)",
                (
                    normalize(row.get("SCP_Number")),
                    normalize(row.get("ServerName")),
                    normalize(row.get("Service")),
                    binding,
                    binding.lower() if binding else None,
                ),
            )

    for yaml_file in find_files(input_dir, "scenario.yaml") + find_files(input_dir, "scenario.yml"):
        try:
            parsed = yaml.safe_load(yaml_file.read_text(encoding="utf-8"))
        except Exception:
            continue
        if parsed is None:
            continue
        for record in extract_scalar_records(parsed, str(yaml_file.relative_to(input_dir))):
            cur.execute(
                "INSERT INTO workflow_records VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    record.workflow_file,
                    record.workflow_name,
                    record.yaml_path,
                    record.field_name,
                    record.field_value,
                    record.request_number,
                    record.transaction_name,
                    record.script_name,
                    record.service_binding,
                    record.server_name,
                    record.step_name,
                    record.raw_context,
                ),
            )

    cur.execute("DELETE FROM metadata")
    cur.executemany(
        "INSERT INTO metadata VALUES (?, ?)",
        [
            ("source_dir", str(input_dir)),
            ("file_count_prg", str(len(list(input_dir.glob('prg_metadata.csv'))))),
            ("file_count_tdb", str(len(list(input_dir.glob('tdb_metadata.csv'))))),
            ("file_count_scp", str(len(list(input_dir.glob('scp_definitions.csv'))))),
            ("workflow_file_count", str(len(find_files(input_dir, 'scenario.yaml')) + len(find_files(input_dir, 'scenario.yml')))),
        ],
    )
    conn.commit()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input_dir", type=Path)
    parser.add_argument("output_sqlite", type=Path)
    args = parser.parse_args()

    args.output_sqlite.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(args.output_sqlite) as conn:
        create_schema(conn)
        write_index(conn, args.input_dir)


if __name__ == "__main__":
    main()
