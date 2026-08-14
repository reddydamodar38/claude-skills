#!/usr/bin/env python3
"""Analyze raw Citrix RTMS USR timers across repeated ABLCAPUTIL runs."""

from __future__ import annotations

import argparse
import csv
import json
import re
from collections import Counter, defaultdict
from pathlib import Path


def labeled_path(value: str) -> tuple[str, Path]:
    if "=" not in value:
        raise argparse.ArgumentTypeError("value must be LABEL=PATH")
    label, path = value.split("=", 1)
    if not label.strip() or not path.strip():
        raise argparse.ArgumentTypeError("value must be LABEL=PATH")
    return label.strip(), Path(path.strip())


def release_labels(value: str) -> tuple[str, list[str]]:
    if "=" not in value:
        raise argparse.ArgumentTypeError("release must be NAME=RUN1,RUN2")
    name, labels = value.split("=", 1)
    items = [item.strip() for item in labels.split(",") if item.strip()]
    if not name.strip() or not items:
        raise argparse.ArgumentTypeError("release must be NAME=RUN1,RUN2")
    return name.strip(), items


def bucket(seconds: float) -> str:
    if seconds < 2:
        return "0-2s"
    if seconds < 5:
        return "2-5s"
    if seconds < 10:
        return "5-10s"
    if seconds < 5400:
        return "10-5400s"
    return ">=5400s"


def find_hosts(root: Path, requested: list[str]) -> list[Path]:
    if requested:
        return [root / name for name in requested]
    return sorted(
        (path for path in root.iterdir() if path.is_dir() and re.search(r"(?:CTX|VDA)\d+$", path.name, re.I)),
        key=lambda path: path.name.lower(),
    )


def find_rtms_file(host: Path) -> Path:
    exact = host / f"ablscale1_{host.name}_sladiscrete.csv"
    if exact.exists():
        return exact
    candidates = [path for path in host.glob("*_sladiscrete.csv") if "hsql" not in path.name.lower()]
    if len(candidates) != 1:
        raise FileNotFoundError(f"expected one RTMS SLA file in {host}, found {len(candidates)}")
    return candidates[0]


def scan(path: Path) -> dict:
    buckets = Counter()
    timers = defaultdict(lambda: [0, 0.0, 0.0])
    total = errors = malformed = 0
    seconds_total = 0.0
    start = end = None
    with path.open("r", encoding="utf-8-sig", errors="replace", newline="") as handle:
        for row in csv.reader(handle):
            if len(row) < 4 or not row[2].strip().upper().startswith("USR:"):
                continue
            try:
                duration = float(row[3])
            except ValueError:
                malformed += 1
                continue
            if duration < 0:
                malformed += 1
                continue
            stamp, timer = row[0], row[2].strip()
            start = stamp if start is None or stamp < start else start
            end = stamp if end is None or stamp > end else end
            total += 1
            seconds_total += duration
            buckets[bucket(duration)] += 1
            stat = timers[timer]
            stat[0] += 1
            stat[1] += duration
            stat[2] = max(stat[2], duration)
            properties = " ".join(row[13:]).lower() if len(row) > 13 else ""
            if "status=failure" in properties or "status=error" in properties:
                errors += 1
    timer_rows = [
        {"timer": name, "count": stat[0], "avg_ms": stat[1] * 1000 / stat[0], "max_ms": stat[2] * 1000}
        for name, stat in timers.items()
    ]
    return {
        "file": str(path), "start": start, "end": end, "count": total,
        "avg_ms": seconds_total * 1000 / total if total else None,
        "buckets": dict(buckets), "errors": errors, "malformed": malformed,
        "top_by_max": sorted(timer_rows, key=lambda row: row["max_ms"], reverse=True)[:20],
        "top_by_avg_count5": sorted((row for row in timer_rows if row["count"] >= 5), key=lambda row: row["avg_ms"], reverse=True)[:20],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="append", required=True, type=labeled_path, metavar="LABEL=PATH")
    parser.add_argument("--release", action="append", type=release_labels, default=[], metavar="NAME=RUN1,RUN2")
    parser.add_argument("--host", action="append", default=[], help="expected CTX/VDA directory name; repeat as needed")
    parser.add_argument("--json", dest="json_path", help="write detailed JSON output")
    args = parser.parse_args()

    payload = {"runs": {}, "releases": {}}
    for label, root in args.run:
        hosts = {}
        for host in find_hosts(root, args.host):
            hosts[host.name] = scan(find_rtms_file(host))
        total = sum(row["count"] for row in hosts.values())
        weighted = sum(row["avg_ms"] * row["count"] for row in hosts.values()) / total if total else None
        buckets = Counter()
        for row in hosts.values():
            buckets.update(row["buckets"])
        payload["runs"][label] = {
            "root": str(root), "hosts": hosts, "count": total, "avg_ms": weighted,
            "buckets": dict(buckets), "errors": sum(row["errors"] for row in hosts.values()),
        }

    for name, labels in args.release:
        missing = [label for label in labels if label not in payload["runs"]]
        if missing:
            raise KeyError(f"release {name} references missing runs: {missing}")
        payload["releases"][name] = {
            "runs": labels,
            "mean_run_count": sum(payload["runs"][label]["count"] for label in labels) / len(labels),
            "mean_run_avg_ms": sum(payload["runs"][label]["avg_ms"] for label in labels) / len(labels),
            "mean_bucket_count": {
                key: sum(payload["runs"][label]["buckets"].get(key, 0) for label in labels) / len(labels)
                for key in ["0-2s", "2-5s", "5-10s", "10-5400s", ">=5400s"]
            },
        }

    rendered = json.dumps(payload, indent=2)
    print(rendered)
    if args.json_path:
        Path(args.json_path).write_text(rendered + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
