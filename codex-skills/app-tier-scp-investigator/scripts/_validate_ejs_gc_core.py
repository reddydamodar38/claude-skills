#!/usr/bin/env python3
"""Compare EJS registry properties and GC evidence across baseline/current runs."""

from __future__ import annotations

import argparse
import json
import re
import zipfile
from pathlib import Path


def labeled_path(value: str) -> tuple[str, Path]:
    if "=" not in value:
        raise argparse.ArgumentTypeError("expected LABEL=PATH")
    label, path = value.split("=", 1)
    return label, Path(path)


def read_registry(run: Path, nodes: list[str]) -> dict[int, dict[str, set[str]]]:
    result: dict[int, dict[str, set[str]]] = {}
    for node in nodes:
        for path in (run / node).glob("*regdump*"):
            current = None
            for line in path.read_text(errors="ignore").splitlines():
                section = re.match(r"\s*\[(?:.*[/\\])?(\d+)\]\s*$", line)
                if section:
                    current = int(section.group(1))
                    result.setdefault(current, {})
                elif current is not None and "=" in line:
                    key, value = (part.strip().strip('"') for part in line.split("=", 1))
                    result[current].setdefault(key, set()).add(value)
    return result


def merged_registry(runs, nodes):
    merged: dict[int, dict[str, set[str]]] = {}
    for _, path in runs:
        for sid, props in read_registry(path, nodes).items():
            for key, values in props.items():
                merged.setdefault(sid, {}).setdefault(key, set()).update(values)
    return merged


def number_for(props, terms):
    for key, values in props.items():
        if any(term in key.lower() for term in terms):
            for value in values:
                match = re.search(r"(?:-xmx)?\s*(\d+(?:\.\d+)?)\s*([gmk]?)", value, re.I)
                if match:
                    amount, unit = float(match.group(1)), match.group(2).lower()
                    return amount * {"g": 1024, "m": 1, "k": 1 / 1024}.get(unit, 1)
    return None


def name_for(props, sid):
    for key, values in props.items():
        if key.lower().endswith(("name", "server_name", "servername")) and values:
            return sorted(values)[0]
    return str(sid)


HEAP_RE = re.compile(r"Heap\s+(?:before|after).*?total\s+(\d+)K,\s+used\s+(\d+)K", re.I | re.S)
PAUSE_RE = re.compile(r"(?:Pause|GC).*?(\d+(?:\.\d+)?)\s*(ms|secs?|s)\b", re.I)


def empty_gc():
    return {"peak_heap_mib": None, "events": 0, "full_gc": 0, "max_pause_ms": None, "oom": 0}


def scan_gc(runs, nodes, wanted):
    result = {sid: empty_gc() for sid in wanted}
    for _, run in runs:
        for node in nodes:
            for zpath in (run / node).glob("*.zip"):
                try:
                    with zipfile.ZipFile(zpath) as archive:
                        for entry in archive.namelist():
                            match = re.search(r"cmb_0*(\d+)_pid\d+_GC\.log$", entry, re.I)
                            if not match or int(match.group(1)) not in wanted:
                                continue
                            item = result[int(match.group(1))]
                            text = archive.read(entry).decode(errors="ignore")
                            heaps = [int(used) / 1024 for _, used in HEAP_RE.findall(text)]
                            if heaps:
                                item["peak_heap_mib"] = max(item["peak_heap_mib"] or 0, max(heaps))
                            item["events"] += len(re.findall(r"Heap\s+before", text, re.I))
                            item["full_gc"] += len(re.findall(r"Full GC", text, re.I))
                            item["oom"] += len(re.findall(r"OutOfMemoryError", text, re.I))
                            for amount, unit in PAUSE_RE.findall(text):
                                ms = float(amount) * (1000 if unit.lower().startswith("s") else 1)
                                item["max_pause_ms"] = max(item["max_pause_ms"] or 0, ms)
                except (zipfile.BadZipFile, OSError, KeyError):
                    continue
    return result


def diff(before, after):
    rows = []
    for key in sorted(set(before) | set(after)):
        left, right = sorted(before.get(key, set())), sorted(after.get(key, set()))
        if left != right:
            rows.append({"property": key, "baseline": left or None, "current": right or None})
    return rows


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", action="append", required=True, type=labeled_path)
    parser.add_argument("--current", action="append", required=True, type=labeled_path)
    parser.add_argument("--server-id", action="append", type=int)
    parser.add_argument("--server-ids-file", type=Path)
    parser.add_argument("--nodes", default="ABLSCALE1APP01,ABLSCALE1APP02")
    parser.add_argument("--json", required=True, type=Path)
    args = parser.parse_args()
    nodes = [x.strip() for x in args.nodes.split(",") if x.strip()]
    baseline, current = merged_registry(args.baseline, nodes), merged_registry(args.current, nodes)
    ids = set(args.server_id or [])
    if args.server_ids_file:
        ids.update(int(x) for x in re.findall(r"\d+", args.server_ids_file.read_text()))
    if not ids:
        ids = set(baseline) | set(current)
    bgc, cgc = scan_gc(args.baseline, nodes, ids), scan_gc(args.current, nodes, ids)
    rows = []
    for sid in sorted(ids):
        bprops, cprops = baseline.get(sid, {}), current.get(sid, {})
        bxmx, cxmx = number_for(bprops, ("xmx", "maxheapsize")), number_for(cprops, ("xmx", "maxheapsize"))
        peak = cgc[sid]["peak_heap_mib"]
        pct = peak / cxmx * 100 if peak is not None and cxmx else None
        crossed = bool(peak is not None and cxmx and peak > cxmx)
        if crossed or cgc[sid]["oom"]:
            status = "Not in line"
        elif peak is None or (pct is not None and pct >= 90) or cgc[sid]["full_gc"]:
            status = "Review"
        else:
            status = "In line"
        rows.append({"server_id": sid, "name": name_for(cprops or bprops, sid),
                     "baseline_xmx_mib": bxmx, "current_xmx_mib": cxmx,
                     "xmx_changed": bxmx != cxmx, "property_changes": diff(bprops, cprops),
                     "baseline_gc": bgc[sid], "current_gc": cgc[sid],
                     "current_peak_pct_xmx": round(pct, 1) if pct is not None else None,
                     "observed_xmx_crossing": crossed, "gc_status": status})
    payload = {"baseline_runs": [x[0] for x in args.baseline],
               "current_runs": [x[0] for x in args.current], "servers": rows}
    args.json.parent.mkdir(parents=True, exist_ok=True)
    args.json.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print(f"Wrote {args.json} with {len(rows)} servers")


if __name__ == "__main__":
    main()
