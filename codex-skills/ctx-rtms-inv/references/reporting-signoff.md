# Reporting and sign-off

## Decision language

Lead with exactly one:

- `Sign-off supported`
- `Conditional sign-off`
- `Sign-off blocked`

Tie the decision to measured evidence and list every condition with owner and closure criteria.

## Root-cause structure

For each material finding state:

1. observation and quantified delta;
2. exact evidence and time window;
3. immediate technical cause;
4. evidence excluding alternative causes;
5. remaining uncertainty;
6. action, owner and sign-off impact.

Avoid `No action required` without measurements.

## Word report structure

Use one document with:

- title, scope and verdict;
- executive-summary one-liner;
- short justification at the requested line count;
- key conclusions;
- run matrix and evidence chain;
- DB findings and attribution;
- APP/EJS findings and reconciliation;
- Xmx/property/GC detail;
- SCP detailed analysis;
- Citrix CPU/memory and process attribution;
- Eggplant success and RTMS response/tail analysis;
- cross-tier synthesis;
- investigation/monitoring register;
- formulas, caveats and evidence inventory.

Use tables for exact comparisons and charts only where they clarify release direction, reconciliation, or throughput/latency. Highlight `Investigate`, `Monitor`, and `Closed` distinctly.

## Suggested concise wording pattern

Executive one-liner:

```text
<Release> DB and application performance is <acceptable/not acceptable>: <primary DB result>, while <primary APP/SCP result>; <condition if any>.
```

Short justification:

```text
Across <run count/scope>, <DB metric> changed by <value> and <APP metric> changed by <value>. <Dominant cause> explains the difference, while <latency/GC/wait/capacity evidence> excludes a platform regression. <Sign-off decision> with follow-up on <owned items>.
```

Keep the executive sentence free of secondary detail. Put exceptions and owners in the short justification or investigation register.

## QA checklist

- All supplied runs and expected hosts included.
- Release averages use repeat runs consistently.
- Dashboard/raw definitions and contradictions documented.
- DB CPU distinguished from host CPU.
- SQL and SCP volume normalized.
- EJS RSS multiplied by instance count/node count correctly.
- Xmx assessed with heap-used data, not RSS.
- Exact-window errors separated from pre/post-test noise.
- Citrix process CPU normalized per workflow iteration when counts differ.
- RTMS workflow subset kept distinct from the broader raw USR timer population.
- Transient process-memory peaks separated from sustained average-RSS growth.
- No unsupported package/caller/JDBC causality.
- Required summaries present and within requested line limits.
- DOCX package, headings, tables, charts, links and placeholders validated.
