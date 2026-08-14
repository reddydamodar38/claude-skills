#!/usr/bin/env python3
"""Read-only ABLCAPUTIL run inventory for DB/APP RCA scoping."""

from __future__ import annotations

import argparse
import json
import os
import re
from collections import Counter
from pathlib import Path


PATTERNS = {
    "report_html": lambda n: n.lower() == "report.html",
    "nmon": lambda n: "nmon" in n.lower() and n.lower().endswith(".csv"),
    "awr": lambda n: "awr" in n.lower(),
    "addm": lambda n: "addm" in n.lower(),
    "process_snapshot": lambda n: "ps.vg" in n.lower(),
    "app_server_stats": lambda n: "app_serv_stat" in n.lower(),
    "ngmdump": lambda n: "ngmdump" in n.lower(),
    "registry": lambda n: "regdump" in n.lower() or "registry" in n.lower(),
    "service_monitor": lambda n: "servicemon" in n.lower(),
    "scp_post": lambda n: "post_test_scp" in n.lower(),
    "cmb_archive": lambda n: n.lower().endswith(".zip") and "cmb" in n.lower(),
    "gc_log": lambda n: "gc" in n.lower() and n.lower().endswith((".log", ".txt")),
    "system_info": lambda n: "system_info" in n.lower(),
    "perfmon_csv": lambda n: n.lower().startswith("perfmon_") and n.lower().endswith(".csv"),
    "perfmon_blg": lambda n: n.lower().startswith("perfmon_") and n.lower().endswith(".blg"),
    "rtms_sla": lambda n: n.lower().endswith("_sladiscrete.csv") and "hsql" not in n.lower(),
    "frontend_citrix": lambda n: n.lower().startswith("frontend.citrix."),
}


def parse_run(value: str) -> tuple[str, Path]:
    if "=" not in value:
        raise argparse.ArgumentTypeError("run must be LABEL=PATH")
    label, raw_path = value.split("=", 1)
    if not label.strip() or not raw_path.strip():
        raise argparse.ArgumentTypeError("run must be LABEL=PATH")
    return label.strip(), Path(raw_path.strip())


def classify_host(name: str) -> str:
    upper = name.upper()
    if re.search(r"DB\d+$", upper):
        return "DB"
    if re.search(r"APP\d+$", upper):
        return "APP"
    if re.search(r"(?:CTX|VDA)\d+$", upper):
        return "CTX"
    return "OTHER"


def scan_host(host: Path, max_depth: int, sample_limit: int) -> dict:
    counts = Counter()
    samples = {key: [] for key in PATTERNS}
    errors = []
    base_depth = len(host.parts)
    for current, dirs, files in os.walk(host):
        current_path = Path(current)
        depth = len(current_path.parts) - base_depth
        if depth >= max_depth:
            dirs[:] = []
        dirs[:] = [d for d in dirs if d.lower() not in {".git", "__pycache__"}]
        for filename in files:
            rel = str((current_path / filename).relative_to(host))
            for key, matcher in PATTERNS.items():
                if matcher(filename):
                    counts[key] += 1
                    if len(samples[key]) < sample_limit:
                        samples[key].append(rel)
    return {
        "path": str(host),
        "type": classify_host(host.name),
        "evidence_counts": dict(sorted(counts.items())),
        "samples": {key: value for key, value in samples.items() if value},
        "errors": errors,
    }


def scan_run(label: str, root: Path, max_depth: int, sample_limit: int) -> dict:
    result = {"label": label, "path": str(root), "exists": root.exists(), "hosts": []}
    if not root.exists():
        result["error"] = "path does not exist or is not accessible"
        return result
    try:
        children = sorted((p for p in root.iterdir() if p.is_dir()), key=lambda p: p.name.lower())
    except OSError as exc:
        result["error"] = str(exc)
        return result
    likely_hosts = [p for p in children if classify_host(p.name) != "OTHER"]
    if not likely_hosts:
        likely_hosts = [root]
    result["hosts"] = [scan_host(host, max_depth, sample_limit) for host in likely_hosts]
    result["db_hosts"] = sum(1 for host in result["hosts"] if host["type"] == "DB")
    result["app_hosts"] = sum(1 for host in result["hosts"] if host["type"] == "APP")
    result["ctx_hosts"] = sum(1 for host in result["hosts"] if host["type"] == "CTX")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="append", required=True, type=parse_run, metavar="LABEL=PATH")
    parser.add_argument("--json", dest="json_path", help="write JSON inventory")
    parser.add_argument("--max-depth", type=int, default=5, help="maximum directory depth below each host")
    parser.add_argument("--sample-limit", type=int, default=5, help="sample paths retained per evidence type")
    args = parser.parse_args()

    inventory = {
        "runs": [scan_run(label, path, args.max_depth, args.sample_limit) for label, path in args.run]
    }
    inventory["summary"] = {
        "run_count": len(inventory["runs"]),
        "accessible_runs": sum(1 for run in inventory["runs"] if run["exists"] and not run.get("error")),
        "db_hosts": sum(run.get("db_hosts", 0) for run in inventory["runs"]),
        "app_hosts": sum(run.get("app_hosts", 0) for run in inventory["runs"]),
        "ctx_hosts": sum(run.get("ctx_hosts", 0) for run in inventory["runs"]),
    }
    rendered = json.dumps(inventory, indent=2)
    print(rendered)
    if args.json_path:
        Path(args.json_path).write_text(rendered + "\n", encoding="utf-8")
    return 0 if inventory["summary"]["accessible_runs"] == inventory["summary"]["run_count"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
