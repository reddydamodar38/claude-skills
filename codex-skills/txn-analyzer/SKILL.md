---
name: txn-analyzer
description: Normalize flat files for transaction metadata, request numbers, server/service bindings, and Gatling workflow scenario YAML files. Use when mapping transactions to scripts, servers, services, bindings, workflows, or when investigating a slow transaction with AWR, long-running session data, or repository scenario files.
---

# Transaction Workflow Investigator

## Overview

Use this skill to build and query a local evidence map from flat CSV files and workflow scenario YAML files. Treat request numbers, script names, service bindings, server definitions, v500 schema and workflow steps as separate sources of evidence, then join them into one investigation view.

## Contextual usage

AWR reports and GC_WorkflowResult.csv supplied typically come from hour long fixed workload, fixed duration non-functional test replicating clinical workflows for an electronic health record environment.  
Most data user and patient data is sythetically generated so there could be issues with unrealistic build data.
Gatling workflows simulating clinical workflows, consist of many transactions per workflow.  
Gatling workflows send headless transactions to the application tier which is where the servers/services are running.  The servers which are connected to the clinical v500 database, then process these transactions and potentially make calls to the database to get a reply.
The scenario.yaml file for a workflow is simulating a single iteration for that workflow.  Tests consists of many users per workflow.

## Core workflow

1. Load the input files.
2. Normalize missing values such as blank strings and `tba`.
3. Join by exact request number first.
4. Join by exact binding next.
5. Use workflow scenario files as supporting evidence, not as sole proof, unless they explicitly name the same request, script, or binding.
6. Label every relationship with its match method and confidence.
7. Separate explicit facts from inferred matches.

## Parent-script call-chain tracing

When an AWR SQL comment identifies a CCL program but that program has no request number or direct workflow match, trace the call chain before declaring the workflow unknown.

1. Resolve the child program's `prg_metadata.csv` file path.
2. Open that source file from the configured program-source repository and identify its SQL operation and immediate caller names.
3. Search the same repository for `execute <child_program>` calls.
4. For each parent program, resolve its `prg_metadata.csv` row. Continue upward until a parent has an exact request number or no source caller is found.
5. Map each request number through `tdb_metadata.csv`.
6. Search the configured Gatling repository's `scenario.yaml`, `scenario-data.yaml`, and `Results/replies.yaml` for the parent script name, request number, or transaction name.
7. Report the full chain: workflow -> request -> parent program(s) -> child program -> SQL ID.

Do not label a workflow as confirmed unless a Gatling artifact contains an exact request number, transaction name, or script reference. Label source-only callers as potential paths. Use the repository branch matching the tested deployment; state the branch when it is not confirmed.

## Source files

Use these inputs together when available:

- `prg_metadata.csv` for script file path, script name, request number, and product.  Use the script name instead of the script file path unless specified.
- `tdb_metadata.csv` for transaction name, request number, request type, and service binding
- `scp_definitions.csv` for server or service definitions and their bindings
- `scenario.yaml` files for workflow name (which is the folder name where the scenario.yaml resides within, workflow structure, step order, branches, transaction references, and execution context)
- `v500_tables.txt` all the tables and their tablespaces for the v500 database where the tests are being executed against, useful for analyzing with AWR Reports
- `v500_columns.txt` all the tables and their columns for the v500 database where the tests are being executed against, useful for analyzing with AWR Reports
- `v500_indexes.txt` all the INDEX_NAME, TABLESPACE_NAME,VISIBILITY INDEX_TYPE,UNIQUENESS,COLUMN_NAME for the v500 database where the tests are being executed against, useful for analyzing with AWR Reports


## Matching precedence

Prefer matches in this order:

1. Exact request number
2. Exact binding
3. Exact transaction name
4. Exact script name
5. Exact server or service name
6. Workflow scenario references that name the same request, script, or binding
7. Naming conventions or other inferred clues

## Investigation output

Return a compact map with these fields when possible:

- request number
- transaction name
- script name
- file path
- service binding
- server number
- server name
- service name
- workflow or scenario name
- step or branch context
- evidence
- confidence

## Slow-transaction triage

When the user provides AWR or long-running transaction evidence, use the mapping to decide whether the slowdown is most likely in:

- the workflow path
- a specific `.prg` script
- a server or service binding
- the database / SQL layer

Do not claim root cause from the flat files alone. Use AWR or session evidence to support DB-time conclusions.

## Delegation to scripts

Use the bundled scripts when you need repeatable parsing or indexing:

- `scripts/build_index.py` to build the SQLite index from CSV and YAML sources
- `scripts/query_index.py` to search the index by request number, transaction, script, binding, server, or workflow

## Guardrails

- Keep raw source rows available for evidence.
- Preserve unknown or missing values instead of inventing them.
- Mark partial workflow matches as inferred.
- If multiple records share a request number, surface all candidates.
- If scenario YAML uses different key names, preserve the raw YAML and extract best-effort fields.
