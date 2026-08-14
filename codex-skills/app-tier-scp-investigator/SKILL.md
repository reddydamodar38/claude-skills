---
name: app-tier-scp-investigator
description: Analyze Millennium Application-tier performance and EJS/SCP behavior from Insight Analyzer report.html files and ABLCAPUTIL run artifacts. Use for App-tier CPU or memory increases, EJS RSS/PSS/Xmx comparisons, registry-property drift, GC health and heap-limit validation, SCP message-count increases, caller/correlation tracing, release sign-off findings, and Excel/Word investigation reports comparing one or more baseline and current runs.
---

# App Tier and SCP Investigator

Analyze the exact run set embedded in the Insight report. Never assume that the newest result directory belongs to the report.

## Core workflow

1. Read the report timestamp and embedded test names.
2. Extract executive CPU/memory, per-node Application-tier memory, and the complete EJS table with `scripts/inspect_insight.py`.
3. Reconcile EJS memory using `references/metrics-and-signoff.md`.
4. Compare EJS registry properties across every baseline and current run, not only one representative run.
5. Validate heap against Xmx and GC logs with `scripts/validate_ejs_gc.py`.
6. For SCP increases, normalize cumulative message counters to first-to-last test deltas and run `scripts/analyze_scp.py`.
7. Produce a decision-oriented finding: exact run scope, quantified delta, dominant contributors, property/Xmx status, GC status, risks, and sign-off recommendation.

Read `references/cross-tier-correlation.md` whenever DB findings, JDBC pools, or added Java services are proposed as contributors to Application-tier memory.

## Insight report extraction

Run:

```powershell
python scripts/inspect_insight.py --report "\\server\share\output\report.html" --json report.json --ejs-csv ejs.csv
```

Confirm the embedded run names, Application-tier CPU and memory, APP01/APP02 differences, every EJS row, and any contradiction between generated prose and numeric tables. Treat numeric tables as authoritative and flag contradictions before sign-off.

## EJS memory investigation

Insight `Avg RSS (MiB)` is a per-instance metric. Calculate average-node contribution as:

```text
RSS difference per instance * total instances / application-node count
```

Report gross positive growth, negative offsets, and net EJS growth. Reconcile net EJS growth to the Application-tier delta.

Run registry/GC validation:

```powershell
python scripts/validate_ejs_gc.py `
  --baseline "GA_R34=\\server\...\R34_MidLevel" `
  --baseline "GA_R35=\\server\...\R35_MidLevel" `
  --current "TP_R08=\\server\...\R08_MidLevel" `
  --current "TP_R11=\\server\...\R11_MidLevel" `
  --server-ids-file increased_ids.txt `
  --json ejs-validation.json
```

Do not compare RSS directly to Xmx as a breach test. RSS includes heap, committed-but-unused heap, metaspace, code cache, thread stacks, direct buffers, JNI/native allocations, and mapped/shared libraries. A heap-limit check requires GC heap-used data versus Xmx.

Check every increased EJS for Xms/Xmx and instance changes, all registry-property differences, OOM/quick-crash evidence, peak heap versus Xmx, Full GC counts, pause regression, and missing/incompatible GC evidence. Use `In line`, `Review`, or `Not in line`; never label missing peak data as zero usage.

## SCP message investigation

SCP `Message count` is cumulative since process start. Compare first and last test samples; do not present the final counter as queue depth.

```powershell
python scripts/analyze_scp.py `
  --server-id 2066 `
  --run "GA=\\server\...\GA_R34" `
  --run "R08=\\server\...\TP_R08" `
  --run "R11=\\server\...\TP_R11" `
  --json scp-2066.json
```

Investigate test-window delta/rate, service split, caller/transaction/user/status/latency/errors/retries, total caller workload, root correlation IDs, and originating CPM/EJS transaction. Compare package/JAR changes only after caller attribution. Separate increased successful throughput from backlog, retry storm, or server failure.

## Sign-off output

Lead with `Sign-off supported`, `Conditional sign-off`, or `Sign-off blocked`. For each material EJS, state server ID/name, RSS increase per JVM and average-node contribution, Xmx/property status, heap-limit/GC/OOM/crash evidence, and the required action.

Avoid vague `No action required` findings without measurements and supporting evidence. For Excel or Word deliverables, load workspace dependencies first and include summary, all increased EJS rows, material contributors, property changes, GC detail, reconciliation, scope, methodology, and caveats.
