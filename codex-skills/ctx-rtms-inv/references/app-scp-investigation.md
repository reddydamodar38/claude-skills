# Application-tier, EJS, and SCP investigation

## Contents

1. Host CPU and memory
2. EJS reconciliation
3. Xmx, properties, heap and GC
4. SCP normalization and tracing
5. Classification

## 1. Host CPU and memory

Analyze every APP node and repeat run. Report release-average mean/max CPU and memory, then retain per-node values to expose imbalance.

- Reconcile dashboard and raw nmon by direction and aggregation scope.
- Treat raw `total-free` memory as cache-inclusive unless proven otherwise.
- Check paging, swap, run queue and sustained threshold duration before calling memory or CPU pressure.

## 2. EJS reconciliation

Insight `Avg RSS (MiB)` is per JVM instance.

```text
both-node contribution = RSS difference per JVM * total instances
average-node contribution = both-node contribution / APP node count
net EJS change = gross positive contributions + negative offsets
```

Report:

- per-JVM average and maximum RSS;
- total/average-node contribution;
- instance-count changes;
- gross positive growth, negative offsets and net change;
- reconciliation to tier-level APP memory.

Do not compare RSS directly to Xmx as a heap breach. RSS also includes metaspace, code cache, stacks, direct/native allocations, JNI and mapped/shared libraries.

## 3. Xmx, properties, heap and GC

Compare all baseline and current runs for every material EJS:

- Xms/Xmx and instance count;
- registry/property differences;
- peak heap used versus Xmx;
- GC event and Full GC counts;
- maximum/percentile pause where available;
- OOM and quick-crash signatures;
- missing or incompatible GC evidence.

Classify:

- `In line`: no OOM/crash/crossing, no new Full GC regression, no material pause regression.
- `Review`: peak heap >=90% Xmx, unchanged pre-existing Full GC, material pause increase, or required peak telemetry unavailable.
- `Not in line`: OOM/crash, observed limit failure, new repeated Full GC, or severe current-build pause regression.

Never report missing peak data as zero.

## 4. SCP normalization and tracing

SCP `Message count` is cumulative since process start. Use exact test-window deltas:

```text
messages = post-test counter - pre-test counter
rate = messages / test duration
CPU per message = process CPU delta seconds * 1000 / messages
```

For every material increase, capture:

- server entry/name and service split;
- resets/new instances;
- caller, transaction, user and originating CPM/EJS path;
- status distribution, weighted average latency, P95/P99/max and >1s/>5s counts;
- errors, timeout, OOM and crash evidence inside the exact window;
- root correlation IDs, repeated groups and max calls per root;
- process CPU and CPU/message.

Separate pre-test/post-test exceptions from in-window evidence. A final counter is not queue depth.

Interpretation:

- higher successful volume with stable/improved latency and CPU/message = healthy throughput;
- more root groups with stable max calls/root = broader workload/caller coverage;
- more calls within the same roots/transactions = call-path amplification or retries;
- errors/timeouts, rising latency and repeated correlations = possible retry/server failure;
- uneven repeat-run volumes = workload/data/test-phasing concern until proven otherwise.

Attribute the increase to caller/transaction before comparing SCP packages or proposing server tuning.

## 5. Classification

Support APP/SCP sign-off when host performance is stable/improved, configuration is consistent, and no OOM/crash/Xmx crossing/new GC regression exists.

Use conditional sign-off for near-Xmx servers, unchanged baseline Full GC, missing GC telemetry, numeric/prose contradictions, caller-side behavior requiring ownership, or material workload mismatch.

Block sign-off for unexplained OOM/crash, heap-limit failure, severe pause/Full GC regression, retry storm, sustained saturation, or unowned severe performance regression.
