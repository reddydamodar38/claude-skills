references/repo-source.md
# Gatling workflow repository

## Source

- Repository: https://github.cerner.com/abilities-center/ABL_VA_NBS
- Branch: main
- Gatling root: `Gatling/`

## Workflow layout

For workflow `<workflow_name>`:

- Scenario: `Gatling/<workflow_name>/scenario.yaml`
- Scenario data: `Gatling/<workflow_name>/scenario-data.yaml`
- Transaction replies: `Gatling/<workflow_name>/Results/replies.yaml`

## How to use this reference

When GC results identify a workflow:

1. Resolve the exact workflow folder name from the GC workflow name.
2. Read `scenario.yaml` to identify the transaction sequence, repetitions,
   branches, and request/script references for one iteration.
3. Read `scenario-data.yaml` only when input data or data volume may explain
   the behavior.
4. Read `Results/replies.yaml` to identify the response returned by the
   corresponding transaction.
5. Use scenario evidence to support a workflow relationship; do not treat it
   alone as proof that a database SQL ID belongs to the workflow.

## Matching rules

Prefer, in order:

1. Exact workflow folder name.
2. Exact transaction/request name in `scenario.yaml`.
3. Exact request number.
4. Exact mapped script name from `prg_metadata.csv`.
5. Naming similarity, labeled as inferred.

## Output for workflow questions

Report:

- workflow name;
- scenario step/branch;
- transaction/request name and request number;
- mapped script and source path;
- relevant scenario-data inputs;
- reply/result evidence;
- match method and confidence.

## Limitations

A Gatling scenario describes one simulated workflow iteration. It establishes
that a transaction is in the workflow, but does not by itself attribute an
AWR/SQL ID to that workflow. Use isolated-run ASH or SQL trace data for that.


# Program source

- Repository: https://github.cerner.com/millennium/ml-native
- Branch: 2018.next
- Path base: repository root
- Path normalization: convert `\` in `prg_metadata.File` to `/`
- `prg_metadata.csv` `File` column: relative to this repository root
- Script lookup order:
  1. exact RequestNumber
  2. exact ScriptName
  3. open the mapped `File` path