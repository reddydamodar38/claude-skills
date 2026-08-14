# Citrix presentation-tier investigation

## Contents

1. Scope and report extraction
2. CPU and process attribution
3. Memory and peak interpretation
4. Eggplant success
5. RTMS response
6. RCA and sign-off rules

## 1. Scope and report extraction

Confirm every expected CTX/VDA host in every repeat run. Verify a process data source (`Perfmon_*.csv` or `.blg`) and an RTMS source (`*_sladiscrete.csv`) for each host/run.

Extract these Insight report sections when present:

- `Eggplant Success`
- `RTMS USR Timers Buckets`
- `Presentation Tier` / `Windows Per Process`
- `Workflow Per Process CPU Data`
- `Workflow Per Process Memory Data`
- `Workflow to RTMS Timer Data`

Retain both release aggregates and repeat-run evidence. Report table values are authoritative when generated prose conflicts with them.

## 2. CPU and process attribution

Report presentation-tier mean and maximum CPU. An unchanged 100% maximum is not a current-build regression by itself; evaluate mean CPU, duration, per-process CPU, repeat consistency, memory, and RTMS impact.

From `Windows Per Process`, compare:

- process count;
- total CPU usage/ticks;
- dominant processes and absolute/relative change;
- the sum across reported process types.

Use `Workflow Per Process CPU Data` to normalize workload:

```text
CPU per iteration = process CPU usage / successful or completed iterations
```

Prefer the report's supplied per-iteration value when available. If total CPU falls only because executions fall, describe workload reduction. If per-iteration CPU also falls, describe improved process efficiency.

Classify a tiny percentage increase on a very small CPU baseline by absolute milliseconds before calling it material.

## 3. Memory and peak interpretation

Report presentation-tier average and maximum memory, then process count, average RSS and peak RSS.

- Use average RSS to evaluate sustained footprint.
- Use peak RSS to locate transients and child-process bursts.
- Do not call one peak a leak when average RSS, process count, total tier memory and repeat behavior are flat or lower.
- For browser processes such as `msedgewebview2.exe`, consider child-process creation and workflow-specific page content.

For every material peak, state the workflow, process, GA/TP average RSS, GA/TP peak RSS, process count, CPU direction, and whether the observation repeats.

## 4. Eggplant success

Summarize successes, failures and reported workflow success percentages. Reconcile the accounting:

- a lower percentage with a higher failure count is a direct reliability regression;
- a lower percentage with zero failures may be an incomplete, aborted or missing iteration;
- an improved failure total does not close a specific workflow regression.

Do not attribute Eggplant failures to Citrix saturation without aligned CPU, memory, session and RTMS evidence. Route screenshots, exceptions and affected users/iterations to the workflow owner.

## 5. RTMS response

Analyze two populations separately:

1. report workflow-mapped timers;
2. broader raw `USR:` timers from every CTX/VDA host.

For the report:

- compare timer bucket counts and percentage-point shifts;
- compute weighted average response from timer count and average duration;
- count improved/worsened timer rows;
- estimate or count >5-second observations;
- list localized average/max/tail regressions with sample counts.

For raw SLA-discrete files, run `scripts/analyze_citrix_rtms.py`. The typical row has timestamp at index 0, timer name at index 2, duration in seconds at index 3, and optional status properties later in the row.

Use these buckets:

- 0-2 seconds;
- 2-5 seconds;
- 5-10 seconds;
- 10-5,400 seconds;
- >=5,400 seconds as invalid/extreme review.

Calculate:

```text
weighted average ms = sum(duration seconds) * 1000 / timer count
bucket share = bucket count / total timer count * 100
```

Compare each repeat run and each host release average. Keep report and raw absolute counts separate because the raw population is normally broader.

Interpret localized tails carefully:

- improved overall/host RTMS with a few higher maxima = transaction-specific tail, not tier-wide Citrix regression;
- higher average and tail on one workflow = trace the exact application/DB transaction timestamp;
- multiple hosts and repeats degrading with CPU/memory pressure = possible presentation-tier capacity issue;
- no `status=failure/error` in raw timers supports transport/execution health but does not close Eggplant functional failures.

## 6. RCA and sign-off rules

Support Citrix sign-off when mean CPU/memory, normalized process CPU, average RSS and RTMS are stable/improved across repeats, even if an unchanged transient maximum exists.

Use conditional sign-off when a repeated material process-memory peak, sustained near-capacity CPU, unexplained host imbalance, or broad RTMS slow-tail regression requires ownership.

Block sign-off for sustained saturation with response degradation, widespread RTMS errors/timeouts, repeated memory growth/paging, or an unowned severe workflow failure pattern.

Always separate:

- Citrix capacity/tuning conclusions;
- workflow functional failures;
- application/DB transaction tails;
- test-accounting or observability gaps.
