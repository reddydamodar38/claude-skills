---
name: sqlplus
description: Connect to Oracle DB using sqlplus/SQLcl and run SQL queries with either explicit credentials or named DB environments (FPABL, ABLFHIR, FPSG). Use when users ask to execute Oracle SQL, validate schema data, or pull result sets from Oracle instances.
---

# SQLPlus Oracle Query Runner

## Inputs
- Query input:
  - `-Query` for inline SQL
  - or `-QueryFile` for `.sql` files
- Connection input (choose one mode):
  - Alias mode: `-DbEnv FPABL|ABLFHIR|FPSG`
  - Explicit mode: `-ConnectionString` or `-TnsName` plus `-UserName` and password
- Password can be provided by:
  - `-Password`
  - `ORACLE_DB_PASSWORD` environment variable
- Optional output settings:
  - `-OutputFormat table|csv|json`
  - `-OutFile` for saving result text
- Safety:
  - Script is hard-locked to allow only read-only `SELECT`/`WITH` SQL (no runtime override flag)


- `FPSG`
  - `UserName`: `v500`
  - `Password`: `CERner##_123ORA`
  - `ConnectionString`: `10.37.174.186:1521/sfpsg.world`
## Workflow
1. Validate Oracle client availability (`sqlplus` preferred, fallback `sql`).
2. Resolve connection from `-DbEnv` or explicit inputs.
3. Execute query from inline SQL or file.
4. Return result set in requested format.
5. Optionally write output to local file.

## Run
Use named environment:
`pwsh -NoProfile -File "C:/Users/prakash/.codex/skills/sqlplus/scripts/run_oracle_query.ps1" -DbEnv "FPABL" -Query "select sysdate from dual" -OutputFormat table`

Use explicit connection:
`pwsh -NoProfile -File "C:/Users/prakash/.codex/skills/sqlplus/scripts/run_oracle_query.ps1" -ConnectionString "db-host:1521/ORCLPDB1" -UserName "app_user" -Password "<password>" -Query "select sysdate from dual" -OutputFormat table`

Run query file and save output:
`pwsh -NoProfile -File "C:/Users/prakash/.codex/skills/sqlplus/scripts/run_oracle_query.ps1" -DbEnv "ABLFHIR" -QueryFile "C:/path/query.sql" -OutputFormat csv -OutFile "C:/path/result.csv"`

Run query (hard lock always applies):
`pwsh -NoProfile -File "C:/Users/prakash/.codex/skills/sqlplus/scripts/run_oracle_query.ps1" -DbEnv "ABLFHIR" -Query "select * from dual"`

## Notes
- Alias mode (`-DbEnv`) auto-loads username/password/connection.
- Explicit mode allows full override for any other Oracle environment.
- For non-SELECT statements, script exits non-zero on Oracle errors.
- Hard lock: non-read-only SQL is blocked before executing against Oracle.
- Keep long SQL in `-QueryFile` to avoid escaping issues.

