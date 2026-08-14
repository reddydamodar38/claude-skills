#!/usr/bin/env python3
import argparse
import csv
import json
import re
from pathlib import Path

try:
    from lxml import html
except ImportError as exc:
    raise SystemExit("lxml is required. Load workspace dependencies or install lxml in a workspace-local target.") from exc


def grid(table):
    rows = table.xpath("./thead/tr|./tbody/tr|./tr")
    output, spans = [], {}
    for r, tr in enumerate(rows):
        row, col = [], 0
        for cell in tr.xpath("./th|./td"):
            while (r, col) in spans:
                value, remaining = spans.pop((r, col)); row.append(value)
                if remaining > 1: spans[(r + 1, col)] = (value, remaining - 1)
                col += 1
            value = " ".join(" ".join(cell.itertext()).split())
            cs, rs = int(cell.get("colspan", "1")), int(cell.get("rowspan", "1"))
            for offset in range(cs):
                row.append(value)
                if rs > 1: spans[(r + 1, col + offset)] = (value, rs - 1)
            col += cs
        while (r, col) in spans:
            value, remaining = spans.pop((r, col)); row.append(value)
            if remaining > 1: spans[(r + 1, col)] = (value, remaining - 1)
            col += 1
        output.append(row)
    width = max(map(len, output))
    return [row + [""] * (width - len(row)) for row in output]


def next_table(root, anchor_id):
    node = root.get_element_by_id(anchor_id).getnext()
    while node is not None and node.tag != "table": node = node.getnext()
    if node is None: raise KeyError(f"Table not found after {anchor_id}")
    return grid(node)


def number(value):
    match = re.search(r"-?\d+(?:\.\d+)?", str(value or "").replace(",", "").strip())
    return float(match.group()) if match else None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", required=True)
    parser.add_argument("--json", required=True)
    parser.add_argument("--ejs-csv")
    args = parser.parse_args()
    report = Path(args.report)
    raw = report.read_text(encoding="utf-8", errors="replace")
    root = html.fromstring(raw)
    run_names = sorted(set(re.findall(
        r"\b20\d{6}_20\d{2}\.[A-Za-z0-9]+_[A-Za-z0-9]+_\d+_R\d+_[A-Za-z0-9]+\b", raw)))
    cpu = next_table(root, "report.extensions.executive_summary_cpu")
    memory = next_table(root, "report.extensions.executive_summary_memory")
    app_memory = next_table(root, "report.memory_millenniumapp")
    anchor = root.get_element_by_id("report.extensions.ejs")
    tables, node = [], anchor.getnext()
    while node is not None:
        text = " ".join(" ".join(node.itertext()).split())
        if node.tag == "p" and "Back to top" in text: break
        if node.tag == "table": tables.append(node)
        node = node.getnext()
    ejs = grid(tables[-1])
    ejs_rows = []
    for row in ejs[3:]:
        ejs_rows.append({
            "entry_id": row[0], "server_name": row[1], "flags": row[2],
            "baseline_instances": number(row[3]), "current_instances": number(row[20]),
            "baseline_oom": number(row[5]), "current_oom": number(row[22]),
            "baseline_crashes": number(row[6]), "current_crashes": number(row[23]),
            "baseline_messages": number(row[7]), "current_messages": number(row[24]),
            "baseline_gc_pause_s": number(row[10]), "current_gc_pause_s": number(row[27]),
            "baseline_heap_before_mib": number(row[11]), "current_heap_before_mib": number(row[28]),
            "baseline_heap_after_mib": number(row[12]), "current_heap_after_mib": number(row[29]),
            "baseline_pss_mib": number(row[13]), "current_pss_mib": number(row[30]),
            "baseline_rss_mib": number(row[14]), "current_rss_mib": number(row[31]),
            "diff_pss_mib": number(row[45]), "diff_rss_mib": number(row[46]),
            "diff_heap_before_mib": number(row[43]), "diff_heap_after_mib": number(row[44]),
        })
    findings = []
    for finding in root.xpath('//div[contains(@class,"findings")]'):
        heading = finding.getprevious()
        while heading is not None and heading.tag not in ("h1", "h2", "h3"): heading = heading.getprevious()
        findings.append({"heading": " ".join(" ".join(heading.itertext()).split()) if heading is not None else "",
                         "text": " ".join(" ".join(finding.itertext()).split())})
    payload = {"report": str(report), "modified_ns": report.stat().st_mtime_ns,
               "embedded_runs": run_names, "cpu_table": cpu, "memory_table": memory,
               "application_memory_table": app_memory, "findings": findings, "ejs": ejs_rows}
    Path(args.json).write_text(json.dumps(payload, indent=2), encoding="utf-8")
    if args.ejs_csv:
        with Path(args.ejs_csv).open("w", newline="", encoding="utf-8-sig") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(ejs_rows[0])); writer.writeheader(); writer.writerows(ejs_rows)
    print(json.dumps({"runs": run_names, "ejs_rows": len(ejs_rows), "json": args.json, "ejs_csv": args.ejs_csv}, indent=2))


if __name__ == "__main__":
    main()
