# `txn-analyzer` usage guide

## What to provide

For a standard performance investigation, provide:

- an AWR report (`.txt`) for the same test interval;
- `GC_WorkflowResults.csv` from the load test;
- optional SQL-area export, such as SQL executions or elapsed time by SQL ID;
- optional production SQL export for workload-coverage comparison.

The skill's bundled metadata supplies the normal request-to-script-to-service map:

- `tdb_metadata.csv` — request number, transaction name, and service binding;
- `prg_metadata.csv` — request number and CCL script name/file;
- `scp_definitions.csv` — server number, server, and service;
- V500 table, column, and index inventories.

The skill's configured workflow repository is used automatically for workflow-path confirmation. It contains each Gatling workflow's `scenario.yaml`, `scenario-data.yaml`, and (when available) `Results/replies.yaml`; name the workflow when you want that context examined.

## Recommended prompt

Use a prompt that names the files and asks for the decision you need. For example:

```text
[$txn-analyzer](C:\\Users\\js026364\\.codex\\skills\\txn-analyzer\\SKILL.md)
Analyze C:\\Users\\me\\Downloads\\GC_WorkflowResults.csv and
C:\\Users\\me\\Downloads\\awr_report.txt. Identify the transactions with
the worst average response time, map them to scripts, service bindings, and
SCP servers, and distinguish database evidence from application evidence.
```

## What the analysis does

1. Normalizes the GC result rows and ranks slow or high-volume transactions.
2. Maps transaction/request names to request numbers, CCL scripts, bindings,
   and SCP servers using exact metadata matches first.
3. Examines AWR top SQL by elapsed time, CPU time, executions, and wait events.
4. Uses V500 schema and index inventory to identify tables, indexes, and likely
   database-side contributors.
5. Uses `scenario.yaml` to show where a mapped transaction occurs in one
   workflow iteration.
6. Produces a concise evidence table and clearly labels exact versus inferred
   associations.

## Interpreting workload-coverage reports

When comparing a test SQL export with production SQL data, workflow columns mean:

| Column | Meaning |
| --- | --- |
| All exec | Total executions reported for that workflow in GC results. |
| Mapped exec | Executions that mapped from GC request to a known script. |
| Mapped | `Mapped exec / All exec`. |
| Prod-covered exec | Mapped executions whose mapped script was present in the supplied production SQL export. |
| Coverage of mapped | `Prod-covered exec / Mapped exec`. |
| Coverage of all | `Prod-covered exec / All exec`. |

This is **script-label coverage**, not proof that every SQL ID belongs to that
workflow. Java/JDBC delegate names and unlabeled SQL cannot be attributed to a
workflow from GC and SQL exports alone.

## Reliable SQL-ID-to-workflow attribution

To attribute all SQL IDs to one workflow, run that workflow in isolation and
collect database evidence for the test window.

- Use ASH to collect `SQL_ID`, `MODULE`, `ACTION`, and request number.
- Do not restrict the collection to `JDBC Thin Client`; retain all modules and
  programs.
- Map actions of the form `TransactionName (request_number)` through
  `tdb_metadata.csv`.
- Treat generic actions such as `TransactionController` as unassigned until
  neighboring ASH samples, application logs, or tracing identify the business
  request.
- Use SQL trace for a truly complete inventory: ASH samples active sessions and
  can miss short SQL statements.

The post-test collector can be run as root and should derive the Oracle
environment from `${test_data}/db_info.txt`, switch to `oracle`, and use OS
authentication (`sqlplus '/ as sysdba'`).

## Useful follow-up prompts

```text
Analyze the top elapsed-time and CPU-time SQL from this AWR report. Identify
the underlying V500 objects and map supported transaction/script relationships.
```

```text
Compare this test SQL export to the production peak-hour export. Create an HTML
report showing SQL-ID overlap, execution/elapsed-time similarity, and clearly
separate unassigned SQL from script-label workflow coverage.
```

```text
For SQL ID 18hz89nvbfath, map the ASH module/action/request number to the
transaction, service binding, SCP server, and potential workflow context.
```

## Evidence rules

- Exact request number or exact script-name matches are high confidence.
- Scenario references support a workflow relationship but do not independently
  prove a SQL-to-workflow relationship.
- AWR and ASH establish database activity; they do not alone establish root
  cause.
- Mark unavailable mappings as unassigned instead of guessing.
