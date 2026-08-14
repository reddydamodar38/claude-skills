---
name: review-report
description: Review HTML performance comparison reports such as report_Final.html or report_ST6_R*.html and produce delta-based review comments. Use when Codex is given a report HTML path and asked to find CPU, memory, Citrix, App tier, Database, Eggplant success, service transaction, SQL statistic, or RTMS timer differences, explain meaningful increases, compare a specific server/SCP across reports, identify report/data mismatches, and prepare paste-ready review comments or investigation-Jira guidance.
---

# Review Report

Review performance-report HTML as a current delta review. Focus on what the tables prove for the supplied report, not on stale narrative text.

## Core Workflow

1. Copy network or mapped-drive HTML reports into the workspace before parsing. If a mapped drive such as `Y:` is not visible, run `net use` and resolve the mapped drive to its UNC path.
2. Parse report tables. Prefer `scripts/extract-report-deltas.ps1` on Windows when PowerShell is available.
3. Ignore existing `Findings` and embedded Jira text unless the user explicitly asks to reuse it or the current table rows still prove the same issue.
4. Identify baseline and current runs from the `Tests` table.
5. When app or DB investigation details are requested, pull supporting run artifacts in addition to the rollup report:
   - `CPUMemSummary.csv` for node-level CPU/memory by app and DB host.
   - App tier delta rows from the report for SCP CPU/memory entries.
   - AWR HTML reports, such as `cabldb1_awr_report_full.html`, for SQL IDs, modules, elapsed time, CPU time, reads, User I/O, waits, and SQL text.
6. Produce a concise, paste-ready review using:
   - `Summary`
   - `Needs Investigation`
   - `Report / Data Mismatch`
   - `Report Enhancements`
   - `No Material Concern`

## Evidence Attribution

When the user asks whether a review came from their data, answer with the concrete source basis:

- Use report HTML files, such as `report_ST6_R48.html`, for report-level App, Database, Citrix, timer, service transaction, Eggplant, and SCP deltas.
- Use `CPUMemSummary.csv` from each run folder for node-level CPU and memory.
- Use AWR HTML files from each DB run folder for SQL IDs, modules, elapsed time, CPU time, physical reads, User I/O, wait events, and SQL text.
- State that SQL ID details come from AWR, and app entries such as `WorkFlow Management`, `Discern Data Access`, `CareCompass`, or `CPM Script` come from app/report delta tables.

## Delta Thresholds

Use these default thresholds unless the user gives different criteria:

- Eggplant success: include current workflow success below `100%`, or any table mismatch involving failures.
- Service transactions: include mean response time increase `>= 5%`.
- App tier SCP CPU: include CPU increase `>= 100s`; also include smaller increases when CPU rose while message volume was flat, lower, or zero.
- App tier SCP memory: include RSS or PSS increase `>= 50 MiB`.
- Citrix workflow CPU: include CPU time per iteration increase `>= 200 ms`.
- Citrix memory: include only material increases; small peak-only changes are usually `No Material Concern`.
- Database: include SQL statistics when the report summary shows executions rising only slightly but CPU, elapsed time, I/O, buffer gets, or disk reads rise more.
- RTMS timers: include average duration increase `>= 500 ms`.

## Focused SCP Comparison

Use this workflow when the user asks about a specific server/SCP, for example `server 373`, `SCP 393`, `why did 2044 change`, or asks to compare two reports for one server.

1. Extract the SCP row from each report's App tier table.
2. State the baseline and current run sets before interpreting the delta. If two reports use different current runs, call that out first because their deltas are not direct same-run comparisons.
3. Confirm whether the baseline run set is the same across reports. If not, do not compare deltas directly without saying the baseline changed.
4. Compare server instances, service count, total SCP messages, CPU seconds, OOM events, quick crashes, average PSS, and average RSS.
5. Calculate CPU percentage increase and CPU per 1k messages:

```text
CPU % increase = ((current CPU - baseline CPU) / baseline CPU) * 100
CPU per 1k messages = CPU seconds / total SCP messages * 1000
```

6. Use CPU per 1k messages to distinguish workload volume from per-message cost. If messages are flat or lower while CPU rises, phrase the issue as not explained by message volume alone.
7. If a newer current run improves versus an older current run but remains above baseline, call it a reduced regression rather than fully resolved.

Prefer this compact comparison shape:

```text
Baseline: <runs>
Current in <report A>: <runs>
Current in <report B>: <runs>

SCP <id> <name>: CPU changed from <baseline>s to <current>s, <+seconds>s / <+percent>%. Messages changed from <baseline> to <current>; CPU per 1k messages changed from <x>s to <y>s. <Interpretation>.
```

## ABLSCALE3 ST App/DB Investigation Pattern

For the known ABLSCALE3 ST comparison where baseline is R43/R46 from `2026.2.01ST6` and current is R20/R48 from `2026.3.01ST6`, use this investigation shape when supported by the provided files:

- Summarize node-level changes from `CPUMemSummary.csv`, especially `ablscale3app01`, `ablscale3app02`, `ablscale3db01`, and `ablscale3db02`.
- Call out when DB pressure is mainly `ablscale3db01` while `ablscale3db02` is flat.
- Correlate App tier entries to DB modules when names and modules align:
  - `2044 WorkFlow Management` with DB module `server_2044` / Financials JDBC.
  - `393 Discern Data Access` with DB module `server_393` / Discern ODA reports.
- For `server_2044`, prioritize SQL IDs such as `f2zc6kmfr5gkv`, `b2h17u69zqxw5`, and `cruqcf9svjxn4` when AWR shows increased elapsed/CPU/I/O or row-lock contention.
- For `server_393`, prioritize SQL IDs such as `gpfxhw7dm2whh` and `6f6tuk944br2h` when AWR shows high physical reads, User I/O, or long-running reporting-style SQL.
- Be careful with execution-count claims. Phrase them as report-scoped when they came from the report, for example: "In the report summary, executions increased only slightly while DB cost increased more." If raw `SQLDBSummary.csv` shows a different trend, call out that the report-level and raw summary views differ instead of blending them.

## App Tier Memory Regdump Cross-Check

When the user asks to explain App tier memory increases with regdump data, compare all runs listed in the report `Tests` table, not just the single path mentioned by the user.

1. Copy or read the app-node regdump artifacts for each included run and app node. Check both common forms:
   - `<run>\ABLSCALE3APP01\ablscale3app01_regdump`
   - `<run>\ABLSCALE3APP01\ablscale3app01_regdump.reg`
   - Repeat for `ABLSCALE3APP02`.
2. For each target SCP, compare a normalized configuration signature across baseline/current runs and both app nodes:
   - `NumInstances`
   - `JavaVersion`
   - `jvmargs`, `jvmargs.memory`, `jvmargs.2`, and other heap or GC arguments
   - server path, command parameters, and other server-specific startup settings when present
   - Extract only the relevant regdump section when possible, for example `[\Node\<appnode>\Domain\ablscale3\Server\<scp>]`, instead of broad `jvmargs` searches that mix unrelated servers
3. If each SCP has only one configuration signature across all regdumps, say the memory increase is not explained by regdump configuration, heap allocation, or instance-count changes. Prefer wording such as:

```text
Regdump comparison across all included tests and both app nodes shows no JVM heap, GC, Java version, or instance-count change for these SCPs. The report memory increase does not appear configuration-driven; it is more likely runtime/native memory variation unless OEM or process-level native allocation data shows otherwise.
```

For the ABLSCALE3 R43/R46 versus R20/R48 comparison, these App tier memory rows have previously followed this pattern when the regdump signatures matched:

- `355 Prescription Benefits`: report RSS increase around `+54 MiB`; config example `3` instances, `-Xmx384M -Xms170M`.
- `369 Financial Clearance Transactions`: report increase around `+44 MiB`; this can fall below the default `50 MiB` memory flag threshold. Config example `1` instance, Java `11`, `-Xmx384M -Xms170M`.
- `388 XML Document Generator`: report RSS increase around `+58 MiB`; config example `2` instances, `-Xmx2048M -Xms1024M`.
- `398 Care Management`: report RSS increase around `+55 MiB`; config example `1` instance, `-Xmx1024M -Xms425M`.
- `509 Clinical Information - Messaging`: report RSS increase around `+86 MiB`; config example `2` instances, `-Xmx1024M -Xms426M -Xmn410M`.
- `519 Revenue Cycle Registration`: report RSS increase around `+56 MiB`; config example `1` instance, `-Xmx768M -Xms323M`.
- `610 NHSN Reporting`: report RSS increase around `+140 MiB`; config example `1` instance, `-Xmx1600M -Xms120M`.
- `2043 Patient and Encounter Accessibility`: report RSS increase around `+125 MiB`; config example `2` instances, `-Xmx1024M -Xms426M`.

Do not reuse these exact values unless the current report and regdump files prove them. Treat them as a reusable comparison pattern and example wording.

## SCP Runtime Evidence Checks

When the user asks why a specific SCP changed, gather only enough supporting evidence to explain the report row. Do not read whole large network files into memory; use `rg`, `Select-String`, filtered `Get-ChildItem`, or narrow line-window reads.

Use this investigation ladder:

1. Confirm same baseline and current runs.
2. Compare workload volume with messages and CPU per 1k messages.
3. Check instance count, service count, OOM, quick crashes, PSS, and RSS.
4. Check regdump for `NumInstances`, `JavaVersion`, JVM heap, GC arguments, server path, and command parameters.
5. Check whether copied CMB logs already exist under a destination such as `\\cernerwhq1\india\ABL\SCP<id>`. If missing and the user wants log evidence, use or suggest the `cmb-copy` workflow for the SCP.
6. Scan copied CMB logs for targeted runtime signals. Prefer a small table by run and node with counts for key patterns.
7. Pull AWR/DB evidence only when a DB-backed cause is suspected or the user asks for root-cause support.

Useful CMB log patterns:

- Stronger runtime signals: `Cannot get Connection from Datasource`, `SQLRecoverableException`, `Got minus one from a read call`, `ORA-`, timeout, retry, pool exhaustion, blocked pool, thread starvation, OOM, heap dump, quick crash.
- Common noise unless materially different between runs: Hibernate metamodel warnings, common startup warnings, healthcheck `UnknownHostException`, and JVM command-line flag output in GC logs.

For CMB signal summaries, prefer a table like:

```text
Run | Node | UnknownHost | CannotGetConnection | ReadMinusOne | GC log MiB
```

When evidence is suggestive rather than conclusive, say so:

```text
The report proves the CPU delta. The CMB logs suggest a runtime DB connection issue may have contributed because <runs> show connection/read-call failures while <runs> do not. This is correlation from app logs, not confirmed root cause without DB/AWR or process-level CPU attribution.
```

## Artifact Locator Map

Use these common ABLCAPUTIL artifact locations when the report points to known ABLSCALE3 runs:

```text
Report HTML: insight/output/report*.html
App CMB ZIP: <run>\ABLSCALE3APP0X\ablscale3app0x_cmb_temp.zip
Copied CMB logs: \\cernerwhq1\india\ABL\SCP<id>\<release>\<run>\ABLSCALE3APP0X
Regdump: <run>\ABLSCALE3APP0X\ablscale3app0x_regdump.reg
Service monitor: <run>\ABLSCALE3APP0X\ablscale3app0x_servicemon_*.csv
Process snapshots: <run>\ABLSCALE3APP0X\ablscale3app0x_ps.*
AWR: <run>\ABLSCALE3DB0X\*_awr_report*.html
```

If the user gives a mapped path like `Y:\insight\output\report.html` and the drive is unavailable, resolve it with `net use` and use the UNC equivalent.

## Evidence Confidence

Separate conclusions by support level:

- Proven by report table: App, Database, Citrix, service transaction, timer, Eggplant, or SCP rows directly parsed from the HTML.
- Supported by logs: CMB, process snapshots, service monitors, or other run artifacts that align with the report delta.
- Possible cause: plausible explanation that still needs AWR, DB, code, or process-level attribution.
- Needs proof: any root-cause claim not directly established by report or supporting artifacts.

Do not turn log correlation into confirmed RCA. State what the report proves and what additional artifact would be needed.

## Review Style

Explain why a row matters, not only the numeric difference.

Use this pattern:

```text
70 CPM Audit Server - CPU increased by 466s with nearly flat message volume. This suggests the increase is not explained by workload volume alone and needs investigation.
```

Do not list every changed row. Keep the review focused on meaningful deltas.

For a "why difference?" answer, use this pattern:

```text
The difference is mainly because the reports use different current runs. <report A> uses <runs>, while <report B> uses <runs>. For SCP <id>, workload volume is <higher/lower/flat>, CPU per 1k messages is <x>, and config <changed/did not change>. Logs show <signal>. So the likely explanation is <summary>, with <needed proof> still needed for RCA.
```

When short on time, provide the minimum useful answer:

- Baseline and current run names.
- CPU seconds, CPU percent, messages, and CPU per 1k messages.
- Whether config changed if checked.
- One likely explanation.
- Evidence still missing for RCA.

## Jira Handling

Do not invent Jira IDs.

When the current report does not contain a trustworthy row-level Jira, say:

```text
Needs investigation Jira.
```

When the user asks for Jira placement, say:

```text
Please place investigation Jiras directly in the affected table rows instead of only listing them in Findings.
```

If an existing report finding appears stale, call it out under `Report / Data Mismatch`.

## Common Report Checks

- Confirm whether Database memory is truly missing. Many reports include DB memory in Executive Summary but omit a detailed Database Tier memory section.
- For process memory, note when the report only provides average or peak RSS/PSS and the reviewer asked for total allocated process memory.
- For `windowssessionmonitor.exe`, distinguish large CPU decreases from CPU regressions. Ask for an explanation of the change, but do not call it an increase.
- Cross-check Eggplant Success against Workflow Per Process tables when one table shows `100%` and another shows failures.
- Treat old Findings text as untrusted until table data supports it.

## Output Skeleton

```text
Pls find review comments for <release/run>. I reviewed the report as a delta against the baseline. Existing Findings/Jiras in the report were not reused unless supported by current table data.

Summary:
...

Needs Investigation:
...

Report / Data Mismatch:
...

Report Enhancements:
...

No Material Concern:
...
```
