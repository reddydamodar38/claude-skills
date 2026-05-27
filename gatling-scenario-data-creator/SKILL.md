---
name: gatling-scenario-data-creator
description: Generate and refresh scenario-data.yaml globalDataSets for already-generated Gatling scripts using remote scenario-data-generator.jar with SQL input, preserve existing data/scenarioDataSets, fix key casing, and then run gatling-runner.
---

# Gatling Scenario Data Creator

## Use When
- You already have a generated Gatling scenario under `C:/Users/prakash/Desktop/project/NBS/gatling/script/<scenario-name>`.
- You want to regenerate only `globalDataSets` in `scenario-data.yaml` from SQL/jar output.
- You want to run the scenario immediately after refresh using [$gatling-runner](C:\Users\prakash\.codex\skills\gatling-runner\SKILL.md).
- You want SQL framed for Oracle Health Millennium (`user.sql`, `patient.sql`) and validated with [$sqlplus](C:\Users\prakash\.codex\skills\sqlplus\SKILL.md) on `ablfhir` or `fpabl`.

## Inputs
- `ScenarioName` (required)
- `UsernameBase` (required): base pattern used for `user.sql` (`LIKE UPPER('<base>%')`)
- `PersonLast` (required): last-name prefix used for `patient.sql` (`LIKE '<last>%')`
- `DbEnv` (optional): `fpabl` (default), `ablfhir`, `fpabl-alt`, or `fpabl2`
- `UserSimpleQuery` (optional): simple user query or `WHERE` predicate; skill extracts/uses predicate and frames full `user.sql`
- `PatientSimpleQuery` (optional): simple patient query or `WHERE` predicate; skill extracts/uses predicate and frames full `patient.sql`
- `SkipSqlplusValidation` (optional switch): skip local SQLplus preview validation
- `TargetAlias` (optional): `ablfhir` (default)

## DB Environments
- `fpabl`
  - `dbusername=v500`
  - `dbpassword=CERner##_123ORA`
  - `dburl=10.37.163.164:1521/sfpabl.world`
- `ablfhir`
  - `dbusername=v500`
  - `dbpassword=v500`
  - `dburl=10.191.200.24:1521/sfpabl.world`
- `fpabl-alt`
  - `dbusername=v500`
  - `dbpassword=CERner##_123ORA`
  - `dburl=10.37.163.164:1521/sfpabl.world`

## Workflow
1. Resolve scenario folder and read existing `scenario.yaml` + `scenario-data.yaml`.
2. Read existing `scenario-data.yaml` `globalDataSets` first and collect existing parameter names (columns).
3. Build Oracle Health Millennium-framed `user.sql` and `patient.sql`:
   - defaults use `UsernameBase` and `PersonLast`
   - when query input is predicate-mode, frame SQL using only columns that exist in current `globalDataSets` (user + patient mappings)
   - default predicate-mode `patient.sql` uses `person + orders + accession_order_r + accession` joins so `order_id` / `accession_nbr` are populated from accession-linked orders
   - if no mapped columns are found for a side, use default framed columns for that side
   - optional `UserSimpleQuery` / `PatientSimpleQuery` can provide simple predicates or full simple queries
4. Save framed SQL under scenario folder: `.../script/<scenario-name>/sql/user.sql` and `.../script/<scenario-name>/sql/patient.sql`.
   - Print the exact effective SQL text for both `user.sql` and `patient.sql` in console output before SQLPlus preview/remote execution.
5. Validate both framed queries with [$sqlplus](C:\Users\prakash\.codex\skills\sqlplus\SKILL.md) (preview first 5 rows) using mapped env:
   - `fpabl|fpabl-alt|fpabl2` -> `FPABL`
   - `ablfhir` -> `ABLFHIR`
6. Create temp workspace and upload SQL files to remote `/root/gatling/gatling-scenario-data-creator-*`.
7. Run remote:
   `java -jar scenario-data-generator.jar -type SQL -dbusername ... -dbpassword ... -dburl ... -transactionname TRANS_NAME -patientsql patient.sql -usersql user.sql -outputfilepath .`
8. Download generated `scenario-data.yaml`.
9. Create a backup of existing local `scenario-data.yaml` before any replacement:
   - backup naming: `scenario-data.yaml.sdc.<yyyyMMdd-HHmmss>.bak`
   - backup location: same scenario folder as `scenario-data.yaml`
10. Replace only local `globalDataSets` block in script scenario-data:
   - preserve existing `data:` and `scenarioDataSets:` content
   - keep only keys that already exist in current `globalDataSets` (no new/extra keys are added)
   - for existing keys, update values from generator output when matching keys are present
   - preserve existing-key casing/order from current `globalDataSets`
   - enforce `authority=ablfhir`, `password=scale`, `current_dt_tm={currentDateTime}` only when those keys already exist
   - keep existing keys that are not produced by jar with their previous values
   - preserve all generated globalDataSets rows (do not collapse to a single row)
11. Cleanup remote and local temp directories.
12. Run [$gatling-runner](C:\Users\prakash\.codex\skills\gatling-runner\SKILL.md) for the same scenario.

## Run
`pwsh -NoProfile -File "C:/Users/prakash/.codex/skills/gatling-scenario-data-creator/scripts/run_gatling_scenario_data_creator.ps1" -ScenarioName "<scenario-name>" -UsernameBase "<username-base>" -PersonLast "<person-last-prefix>" -DbEnv fpabl -TargetAlias ablfhir`

With simple sample queries:
`pwsh -NoProfile -File "C:/Users/prakash/.codex/skills/gatling-scenario-data-creator/scripts/run_gatling_scenario_data_creator.ps1" -ScenarioName "<scenario-name>" -UsernameBase "mike" -PersonLast "smith" -DbEnv ablfhir -UserSimpleQuery "select username from prsnl where username like upper('mike%')" -PatientSimpleQuery "where p.NAME_LAST like 'smith%' and e.ACTIVE_IND = 1"`

Custom patient query template (future query building):
`SELECT p.PERSON_ID, o.ENCNTR_ID, o.order_id, a.ACCESSION FROM person p JOIN ORDERS o ON p.PERSON_ID = o.PERSON_ID JOIN ACCESSION_ORDER_R aor ON aor.order_id = o.order_id JOIN ACCESSION a ON a.ACCESSION_ID = aor.ACCESSION_ID WHERE p.NAME_LAST = 'VAPathNtGenLabMicRegCulStrgTrkPtTwo' AND o.ORDER_MNEMONIC = 'C Wound' ORDER BY p.PERSON_ID`

## Notes
- The skill is non-interactive and continues end-to-end unless there is a hard blocker.
- Remote host/jar location follows the same SSH model as gatling-converter:
  - host alias `ablfhir` -> `10.191.200.22` / `root` / key `%USERPROFILE%/.ssh/id_gatling`
  - jar path: `/root/gatling/scenario-data-generator.jar`
- SQLPlus validation uses [$sqlplus](C:\Users\prakash\.codex\skills\sqlplus\SKILL.md); pass `-SkipSqlplusValidation` if you only want remote jar generation.
- `UserSimpleQuery` and `PatientSimpleQuery` can be either:
  - a simple `WHERE` predicate (inserted into framed SQL), or
  - a full `SELECT ...` query (used as-is).
- Predicate-mode framing is globalDataSets-driven:
  - `user.sql` mapped columns: `authority`, `username`, `user_id`, `prsnl_id`, `password`, `current_dt_tm`, `current_dt_tm_PastNineYears`
  - `patient.sql` mapped columns: `fin_num`, `person_id`, `encntr_id`, `order_id`, `accession_nbr`
- GlobalDataSets merge rule is strict:
  - do not introduce extra properties that are not already present in existing `scenario-data.yaml` `globalDataSets`
