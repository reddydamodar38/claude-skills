#!/usr/bin/env python3
import argparse
import json
import re
import zipfile
from collections import Counter
from pathlib import Path

FIELD = re.compile(r'(\w+)="([^"]*)"')


def parse_pair(value):
    if "=" not in value: raise argparse.ArgumentTypeError("Expected LABEL=PATH")
    label, path = value.split("=", 1)
    return label, Path(path)


def server_block(text, server_id):
    for block in text.split("-------- SERVER "):
        if re.search(rf"(?m)^Entry\s+\.+\s+0*{re.escape(server_id)}\s*$", block): return block
    return None


def field_number(block, name):
    match = re.search(rf"(?m)^{re.escape(name)}\s+\.+\s+(\d+)", block or "")
    return int(match.group(1)) if match else None


parser = argparse.ArgumentParser()
parser.add_argument("--server-id", required=True)
parser.add_argument("--run", action="append", type=parse_pair, required=True)
parser.add_argument("--nodes", default="ABLSCALE1APP01,ABLSCALE1APP02")
parser.add_argument("--json", required=True)
args = parser.parse_args()

nodes = [x.strip() for x in args.nodes.split(",") if x.strip()]
output = {"server_id": args.server_id, "runs": {}}

for label, root in args.run:
    run = {"root": str(root), "nodes": {}}
    for node in nodes:
        folder = root / node
        samples = []
        for path in sorted(folder.glob("*_ngmdump_srv_*.dat")):
            block = server_block(path.read_text(errors="replace"), args.server_id)
            if block:
                samples.append({"sample": path.stem.rsplit("_srv_", 1)[-1], "message_count": field_number(block, "Message count")})
        first = samples[0]["message_count"] if samples else None
        last = samples[-1]["message_count"] if samples else None
        node_result = {"samples": samples, "first": first, "last": last, "test_delta": (last - first) if first is not None else None}

        callers, users, statuses, transactions, durations = Counter(), Counter(), Counter(), Counter(), []
        error_words = 0
        zips = list(folder.glob("*cmb_temp*.zip"))
        if zips:
            with zipfile.ZipFile(zips[0]) as archive:
                out_name = next((n for n in archive.namelist() if re.search(rf"cmb_0*{re.escape(args.server_id)}_0001\.out$", n)), None)
                err_name = next((n for n in archive.namelist() if re.search(rf"cmb_0*{re.escape(args.server_id)}_0001\.err$", n)), None)
                if out_name:
                    for line in archive.read(out_name).decode("utf-8", "replace").splitlines():
                        if not line.startswith("access_log:"): continue
                        row = dict(FIELD.findall(line))
                        callers[row.get("caller", "<missing>")] += 1
                        users[row.get("user", "<missing>")] += 1
                        statuses[row.get("status", "<missing>")] += 1
                        transactions[row.get("transaction_name", "<missing>")] += 1
                        if row.get("duration_ms"): durations.append(float(row["duration_ms"]))
                if err_name:
                    err = archive.read(err_name).decode("utf-8", "replace").lower()
                    error_words = sum(err.count(x) for x in ("exception", " error", "failed", "timeout"))
        durations.sort()
        node_result.update({
            "callers": callers.most_common(), "users_top20": users.most_common(20),
            "statuses": dict(statuses), "transactions": dict(transactions), "error_words": error_words,
            "latency_avg_ms": sum(durations) / len(durations) if durations else None,
            "latency_p95_ms": durations[int(len(durations) * .95)] if durations else None,
            "latency_max_ms": max(durations) if durations else None,
        })
        run["nodes"][node] = node_result
    output["runs"][label] = run

Path(args.json).write_text(json.dumps(output, indent=2), encoding="utf-8")
print(json.dumps({"server_id": args.server_id, "runs": list(output["runs"]), "json": args.json}, indent=2))
