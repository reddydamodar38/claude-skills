# Stale Statistics Operations

## Controller Setup

Run from the existing `node-orchestration` checkout on the configured Linux runner. Verify `hostname`, `id -un`, and `pwd` first. Preserve a dirty checkout and do not expose Git remote URLs.

Set `DOMAIN`, an absolute `SKILL_DIR`, the existing in-container `VAULT_FILE`, the primary `DB_HOST`, and `RESTORE_POINT=ABL_RESTORE_POINT`. Confirm inventory and vault paths exist without reading vault content.

## TACO Command Template

```bash
docker compose run --rm -v "${SKILL_DIR}:/skill:ro" taco \
  ansible-playbook \
  -i "lab_inventory/${DOMAIN}/" \
  -i lab_inventory/lab_groups.yml \
  --vault-password-file "${VAULT_FILE}" \
  /skill/playbooks/stale-stats.yml \
  -e "stale_stats_domain=${DOMAIN}" \
  -e "stale_stats_action=<action>"
```

Supported actions are `restorepoint`, `replace-restorepoint`, `preflight`, `preview`, `queue`, `runners`, `status`, `publish`, and `audit`. Use `stale_stats_db_host=<host>` only when inventory lacks `primaryDB`.

## Restore-point Actions

Create-if-absent:

```bash
docker compose run --rm -v "${SKILL_DIR}:/skill:ro" taco \
  ansible-playbook -i "lab_inventory/${DOMAIN}/" -i lab_inventory/lab_groups.yml \
  --vault-password-file "${VAULT_FILE}" /skill/playbooks/stale-stats.yml \
  -e "stale_stats_domain=${DOMAIN}" -e stale_stats_action=restorepoint \
  -e "stale_stats_restore_point_name=${RESTORE_POINT}"
```

Explicit guarded replacement:

```bash
docker compose run --rm -v "${SKILL_DIR}:/skill:ro" taco \
  ansible-playbook -i "lab_inventory/${DOMAIN}/" -i lab_inventory/lab_groups.yml \
  --vault-password-file "${VAULT_FILE}" /skill/playbooks/stale-stats.yml \
  -e "stale_stats_domain=${DOMAIN}" -e stale_stats_action=replace-restorepoint \
  -e "stale_stats_restore_point_name=${RESTORE_POINT}" \
  -e stale_stats_confirm_replace=true
```

Replacement requires explicit user approval and `stale_stats_confirm_replace=true`. It reports database identity and the old row, drops only the validated name when present, creates `GUARANTEE FLASHBACK DATABASE`, and requires `NEW_RESTORE_POINT=<name>...|GUARANTEE=YES`. Stop on any Oracle failure and inspect current state before retrying. Neither restore-point action runs CCL or application-node tasks.

## Exact CCL Operations

The detached action scripts send the standard `PREVIEW_STALE`, `QUEUE_STALE`, `dm2_dbstats_runner`, and `dm2_publish_dbstats '*','*','PUBLISH'` commands. Queue, preview, and publish run once on the primary application host; a runner starts on every application host.

## Logs and Result Interpretation

Skill-owned logs and `.done` markers remain under `$cer_temp` as `codex_dbstats_*`. A missing marker with a matching `/tmp/codex_dbstats_*.ksh` process means active. Never match or terminate by `cclora` executable name alone.

CCL 9.05.7 return code `1` is successful only when the same log contains `Command executed!` and `SESSION COMPLETE` and no fatal indicator. Preserve complete logs.

## Preview Parser

```bash
expected_csv=$(python3 "${SKILL_DIR}/scripts/resolve-expected-not-queued.py" "${DOMAIN}")
bash "${SKILL_DIR}/scripts/summarize-status.sh" <preview-log> "${expected_csv}"
```

The parser exits `0` for a valid gate, `2` for `FAILURE`, `3` for unexpected `NOT QUEUED`, and `64/66` for invocation/input errors. It matches real CCL rows by `TABLE_NAME`.

Global allowed families are `DM_INFO`, `DM_STAT_TABLE`, `DM_PROCESS_EVENT`, and `DM_PROCESS`. ABLSCALE3 also allows `DM_PROCESS_QUEUE`, `HE_JOB`, and `MP_GROUP_REFRESH_STATE`; these never suppress `FAILURE`.

## Recovery and Publish Gate

Publish only after all runners complete, a fresh preview exits `0`, no skill process is active, and logs meet success rules. Retry failures only while progress occurs. Never add an unexpected object automatically; require evidence or user direction. After publish, run a fresh preview plus `audit` and report the effective policy and evidence.
