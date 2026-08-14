# Metrics and sign-off reference

## Reconciliation

- Insight `Avg RSS (MiB)` is per instance.
- Both-node EJS change = per-instance RSS difference * total instances.
- Average-node contribution = both-node change / application-node count.
- Net EJS = positive contributors + negative offsets.
- Reconciliation percentage = net EJS average-node change / Application-tier average change.

## Memory interpretation

- RSS above Xmx is not a heap breach.
- Heap breach evidence requires heap-used versus Xmx, OOM, or crash evidence.
- Private-dirty/PSS growth with flat after-GC heap suggests committed heap and/or native/off-heap growth, not necessarily a leak.
- Missing GC peak data must be labeled unavailable.

## GC classification

`In line`:

- no OOM or quick crash;
- no observed Xmx crossing;
- no new Full GC regression;
- no material pause regression.

`Review`:

- peak heap reaches 90% of Xmx;
- Full GC exists but is unchanged from baseline;
- pause time materially increases;
- required peak data is unavailable.

`Not in line`:

- OOM or quick crash;
- observed heap crossing/limit failure;
- new repeated Full GC or severe pause regression tied to the current build.

## SCP interpretation

- Final message count is cumulative, not queue depth.
- Normalize to first-to-last test samples.
- All status-200 calls with stable/improved latency indicate successful throughput.
- Attribute the increase to caller and transaction before blaming the SCP server package.
- Equal workload with one extra child request per transaction is a caller-side call-path regression or intentional behavior change.

## Sign-off guardrails

Support sign-off when performance is stable/improved, configuration is consistent, and no OOM/crash/Xmx crossing/new GC regression exists.

Use conditional sign-off when near-Xmx servers, unchanged existing Full GC, narrative/table contradictions, or owned caller-side regressions require tracking.

Block sign-off for unexplained OOM/crash, heap-limit failure, material workload mismatch, or unowned severe performance regression.
