---
name: ctx-rtms-inv
description: Perform end-to-end Millennium Database-tier, Application-tier, and Citrix presentation-tier performance RCA from Insight Analyzer report.html files and ABLCAPUTIL raw run artifacts. Use when comparing GA/baseline and TP/current scale runs; investigating DB, APP, CTX or VDA CPU/memory differences; attributing Oracle AWR/ADDM and host/process load; reconciling EJS RSS/PSS, Xmx, registry properties, heap and GC; analyzing SCP messages and callers; validating Eggplant success, workflow-process CPU/RSS, RTMS timer buckets and per-host response; deciding release sign-off; or producing a detailed Word/text RCA with executive and short-summary wording.
---

# CTX-RTMS-Inv

Investigate the exact baseline/current run set across DB, Application, and Citrix presentation tiers, prove the immediate technical cause of each material difference, and produce an evidence-backed release decision.

## Non-negotiable rules

- Treat source shares as read-only. Stage only required artifacts locally.
- Derive scope from the report or user-supplied run paths. Never substitute the newest directory.
- Compare every supplied repeat run, all APP nodes, and all named CTX/VDA nodes; do not cherry-pick one baseline/current pair.
- Separate dashboard values, raw host values, Oracle metrics, JVM metrics, and SCP counters. Do not compare unlike definitions as if they were identical.
- Prefer numeric tables and raw evidence over generated narrative. Flag contradictions.
- State `observed`, `supported inference`, and `unverified hypothesis` separately.
- Do not call correlation causation. Identify the process/caller/transaction before blaming a release package.

## Workflow

1. Build a run matrix with release, run ID, timestamp, workload, DB host, APP hosts, CTX/VDA hosts, and exact test window.
2. Inventory raw evidence with `scripts/inventory_runs.py`; record missing or inconsistent artifacts before analysis.
3. Extract dashboard DB/APP/Citrix CPU and memory values from `report.html`, when supplied, and retain table/prose contradictions.
4. Execute the DB branch in `references/db-investigation.md` for nmon, AWR/ADDM, wait events, SQL, OS processes, and capacity attribution.
5. Execute the APP/SCP branch in `references/app-scp-investigation.md` for host CPU/memory, EJS RSS, instance counts, Xmx/properties, GC/heap, and normalized SCP behavior.
6. Execute the Citrix branch in `references/citrix-investigation.md` for Perfmon, Windows/workflow process CPU and RSS, Eggplant success, RTMS buckets, workflow timers, and per-host raw response.
7. Correlate tiers only when timestamps and workload evidence align. Validate JDBC/service/session or downstream-transaction claims before using them as causes.
8. Classify every material finding as healthy, monitor, investigate, or blocker and assign an owner/action.
9. Apply `references/reporting-signoff.md` and produce one detailed RCA document plus reusable short and executive wording.

## Start with scope validation

Run:

```powershell
python scripts/inventory_runs.py `
  --run "GA_R34=\\server\share\...\R34_MidLevel" `
  --run "GA_R35=\\server\share\...\R35_MidLevel" `
  --run "TP_R05=\\server\share\...\R05_MidLevel" `
  --run "TP_R20=\\server\share\...\R20_MidLevel" `
  --json run-inventory.json
```

Confirm that each run contains the expected DB host, APP01/APP02 evidence, and every named CTX/VDA host. Stop causal analysis if the compared workload, duration, host topology, or test window is materially different; report the mismatch first.

## DB branch

Read `references/db-investigation.md` whenever DB CPU, DB memory, AWR/ADDM, SQL, waits, or OS process attribution is in scope.

Required output:

- dashboard and raw DB CPU/memory reconciliation;
- full-run and peak-window AWR/ADDM evidence;
- DB CPU versus total host CPU distinction;
- top SQL/waits with workload-normalized interpretation;
- paired process CPU attribution for Oracle and non-Oracle contributors;
- immediate cause, residual uncertainty, action, and sign-off impact.

## APP, EJS, and SCP branch

Read `references/app-scp-investigation.md` whenever APP CPU/memory, EJS, Java heap/GC, SCP, CPM, or caller tracing is in scope.

If the sibling `app-tier-scp-investigator` skill is installed, reuse its deterministic tools:

- `inspect_insight.py` for report extraction;
- `validate_ejs_gc.py` for Xmx/property/GC validation;
- `analyze_scp.py` for normalized SCP/caller/correlation analysis.

Required output:

- APP CPU/memory by release, run, and node;
- EJS gross-positive, negative-offset, and net average-node RSS reconciliation;
- all Xmx, property, instance, heap, GC, OOM, crash, and missing-telemetry findings;
- SCP first-to-last counter deltas, rates, CPU/message, service, caller, transaction, user, status, latency, retry/correlation, and exact-window error evidence;
- server-side versus caller/workload-side RCA.

## Citrix, Eggplant, and RTMS branch

Read `references/citrix-investigation.md` whenever Citrix/CTX/VDA CPU or memory, Windows Perfmon, workflow-process data, Eggplant success, RTMS timers, or presentation-tier response is in scope.

Run the portable raw timer analyzer after staging or directly reading the compact SLA-discrete files:

```powershell
python scripts/analyze_citrix_rtms.py `
  --run "GA_R34=\\server\share\...\R34_MidLevel" `
  --run "GA_R35=\\server\share\...\R35_MidLevel" `
  --run "TP_R05=\\server\share\...\R05_MidLevel" `
  --run "TP_R20=\\server\share\...\R20_MidLevel" `
  --release "GA=GA_R34,GA_R35" `
  --release "TP=TP_R05,TP_R20" `
  --json citrix-rtms.json
```

Required output:

- presentation-tier dashboard CPU/memory and unchanged-maximum interpretation;
- overall Windows process CPU/RSS and process-count comparison;
- workflow CPU per iteration so execution-count differences are normalized;
- workflow average/peak RSS with sustained versus transient-peak interpretation;
- Eggplant success, failure, incomplete/aborted iteration reconciliation;
- report RTMS bucket/weighted-average/tail analysis and raw per-run/per-host validation;
- localized workflow/timer follow-ups separated from tier-wide Citrix capacity findings.

## Cross-tier synthesis

- Align evidence by exact test window before relating DB, APP, and Citrix events.
- Use per-transaction or per-message metrics when volume differs.
- Support a JDBC/service-footprint explanation only after checking JVM/service inventory, pool configuration, and DB sessions/connections.
- Treat stable CPU, response time, paging, GC, and heap headroom as evidence of footprint without pressure.
- Do not attribute a localized RTMS tail to Citrix capacity when mean CPU/memory and normalized process cost improve; trace its application/DB transaction first.
- Keep an unexplained workload mismatch as a sign-off condition even when servers are healthy.

## Deliverables

For a detailed RCA, include:

1. verdict and executive one-liner;
2. short justification capped at the user's requested line count;
3. run scope and methodology;
4. DB CPU/memory, AWR/ADDM, SQL/waits, and process attribution;
5. APP CPU/memory and EJS reconciliation;
6. Xmx/property/GC/heap validation;
7. SCP server and caller RCA;
8. Citrix CPU/memory and process attribution;
9. Eggplant and RTMS presentation-tier response analysis;
10. cross-tier synthesis;
11. investigation/monitoring register with owners;
12. formulas, caveats, and evidence inventory.

For Word output, use the documents skill and complete render/structural QA. If a page renderer is unavailable, state the limitation and still validate package integrity, headings, tables, images, required wording, and unresolved placeholders.

## Completion standard

Do not finish with only a dashboard delta. Finish when the evidence identifies whether the difference is:

- healthy workload growth;
- caller or scenario-volume change;
- Oracle/database workload;
- non-Oracle host activity;
- JVM heap/native footprint or GC behavior;
- SCP retry/error/capacity behavior;
- Citrix process efficiency or sustained memory footprint;
- Eggplant functional/incomplete-iteration behavior;
- RTMS tier-wide response or localized slow-tail behavior;
- observability gap; or
- unresolved and therefore an owned sign-off condition.
