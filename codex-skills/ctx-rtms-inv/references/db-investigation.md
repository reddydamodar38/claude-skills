# Database-tier investigation

## Contents

1. Scope and metrics
2. Host analysis
3. Oracle analysis
4. Process attribution
5. RCA decision rules

## 1. Scope and metrics

Collect the exact test start/end, processor count, memory, DB instance, and repeated run labels. Preserve both dashboard and raw values.

- Host CPU busy = `100 - nmon Idle%`.
- Release average = arithmetic mean of repeated run metrics.
- Report mean, maximum, percentile when available, and duration above a meaningful threshold.
- Do not equate Oracle `DB CPU` with total host CPU. DB CPU is Oracle foreground/background database work; host CPU includes every process and kernel activity.
- Do not equate cache-inclusive `total-free` memory with a dashboard working-set definition.

## 2. Host analysis

Parse nmon for each run:

- mean/max CPU busy and peak timestamp;
- user, system, wait, steal and idle composition;
- memory, paging/swap, run queue, disk and network indicators near the peak;
- repeat-run consistency.

Create a peak window around each maximum. Use paired `ps.vg` snapshots to calculate cumulative CPU time deltas:

```text
process CPU delta = ending cumulative TIME - starting cumulative TIME
average cores = process CPU delta seconds / snapshot interval seconds
host CPU points = average cores / logical processors * 100
```

Separate Oracle, kernel, monitoring/collection, HA/diagnostic, and other application processes. A non-Oracle contributor may explain a host maximum even when AWR reports no DB CPU bottleneck.

## 3. Oracle analysis

Use full-run AWR for overall equivalence and a peak-window AWR/ADDM report for the highlighted maximum.

Capture:

- elapsed time, DB time, DB CPU, average active sessions, executions and transactions;
- load profile normalized per second and per transaction;
- time model and foreground/background split;
- top timed foreground events and wait classes;
- SQL ordered by elapsed time, CPU time, executions, gets and reads;
- ADDM findings and explicit `DB CPU is/is not a bottleneck` evidence;
- I/O latency, log file sync, parse, hard-parse, enqueue, cluster, and segment findings when material.

Normalize SQL changes before calling them regressions:

```text
CPU per execution = SQL CPU seconds / executions
elapsed per execution = SQL elapsed seconds / executions
buffer gets per execution = buffer gets / executions
```

A higher total caused by more executions with stable per-execution cost is workload growth, not necessarily SQL degradation.

## 4. Process attribution

Reconcile observed host CPU delta to process contributors. Quantify each contributor in CPU-seconds, average cores, and host CPU points where possible.

Use precise language:

- `caused by` only when time alignment and quantitative contribution support it;
- `materially contributed to` when it explains part of the delta;
- `coincided with` when logs needed for causal proof are outside scope.

For Oracle diagnostic/HA processes, identify the process and contribution but route the reason for activation to the DBA/AHF owner unless its own logs are present.

## 5. RCA decision rules

Support DB sign-off when:

- AWR/ADDM shows no CPU or critical wait bottleneck;
- SQL cost per execution is stable or improved;
- paging/I/O/run-queue evidence is healthy;
- any host maximum increase is small, bounded, and attributed.

Use conditional sign-off when:

- a non-Oracle process materially contributes but its activation reason is unverified;
- workload or peak-window equivalence is uncertain;
- a dashboard/raw contradiction remains documented but direction is consistent.

Block sign-off for unexplained sustained saturation, severe wait/SQL regression, paging, DB/host errors, or a material unowned workload mismatch.
