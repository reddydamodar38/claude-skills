#!/usr/bin/env python3
"""CLI wrapper with strict Xmx and actual-OOM parsing."""

import argparse
import json
import re
import zipfile
from pathlib import Path

import _validate_ejs_gc_core as core


def xmx_mib(props):
    for key, values in props.items():
        for value in values:
            if "xmx" not in key.lower() and "xmx" not in value.lower():
                continue
            match = re.search(r"-Xmx\s*(\d+(?:\.\d+)?)\s*([gmk]?)", value, re.I)
            if match:
                amount, unit = float(match.group(1)), match.group(2).lower()
                return amount * {"g": 1024, "m": 1, "k": 1 / 1024}.get(unit, 1)
    return None


def scan_actual_oom(runs, nodes, wanted):
    counts = {sid: 0 for sid in wanted}
    pattern = re.compile(r"(?m)^\s*(?:java\.lang\.)?OutOfMemoryError\b")
    for _, run in runs:
        for node in nodes:
            for zpath in (run / node).glob("*.zip"):
                try:
                    with zipfile.ZipFile(zpath) as archive:
                        for entry in archive.namelist():
                            match = re.search(r"cmb_0*(\d+)_pid\d+_GC\.log$", entry, re.I)
                            if match and int(match.group(1)) in wanted:
                                counts[int(match.group(1))] += len(pattern.findall(archive.read(entry).decode(errors="ignore")))
                except (zipfile.BadZipFile, OSError, KeyError):
                    continue
    return counts


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", action="append", required=True, type=core.labeled_path)
    parser.add_argument("--current", action="append", required=True, type=core.labeled_path)
    parser.add_argument("--server-id", action="append", type=int)
    parser.add_argument("--server-ids-file", type=Path)
    parser.add_argument("--nodes", default="ABLSCALE1APP01,ABLSCALE1APP02")
    parser.add_argument("--json", required=True, type=Path)
    args = parser.parse_args()
    nodes = [x.strip() for x in args.nodes.split(",") if x.strip()]
    baseline, current = core.merged_registry(args.baseline, nodes), core.merged_registry(args.current, nodes)
    ids = set(args.server_id or [])
    if args.server_ids_file:
        ids.update(int(x) for x in re.findall(r"\d+", args.server_ids_file.read_text()))
    if not ids:
        ids = set(baseline) | set(current)
    bgc, cgc = core.scan_gc(args.baseline, nodes, ids), core.scan_gc(args.current, nodes, ids)
    boom, coom = scan_actual_oom(args.baseline, nodes, ids), scan_actual_oom(args.current, nodes, ids)
    rows = []
    for sid in sorted(ids):
        bprops, cprops = baseline.get(sid, {}), current.get(sid, {})
        bgc[sid]["oom"], cgc[sid]["oom"] = boom[sid], coom[sid]
        bxmx, cxmx = xmx_mib(bprops), xmx_mib(cprops)
        peak = cgc[sid]["peak_heap_mib"]
        pct = peak / cxmx * 100 if peak is not None and cxmx else None
        crossed = bool(peak is not None and cxmx and peak > cxmx)
        if crossed or cgc[sid]["oom"]:
            status = "Not in line"
        elif peak is None or (pct is not None and pct >= 90) or cgc[sid]["full_gc"]:
            status = "Review"
        else:
            status = "In line"
        rows.append({"server_id": sid, "name": core.name_for(cprops or bprops, sid),
                     "baseline_xmx_mib": bxmx, "current_xmx_mib": cxmx,
                     "xmx_changed": bxmx != cxmx, "property_changes": core.diff(bprops, cprops),
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
