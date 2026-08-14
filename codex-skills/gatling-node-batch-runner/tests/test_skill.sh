#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/bin:$PATH"

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
tmp_dir="/tmp/gatling-node-batch-runner-test-$$"
mkdir -p "$tmp_dir"
trap 'rm -rf "$tmp_dir"' EXIT

assert_contains() {
  local haystack=$1 needle=$2
  grep -F -- "$needle" <<<"$haystack" >/dev/null || {
    printf 'missing expected text: %s\n' "$needle" >&2
    exit 1
  }
}

assert_file_contains() {
  local file=$1 needle=$2
  grep -F -- "$needle" "$file" >/dev/null || {
    printf 'missing %s in %s\n' "$needle" "$file" >&2
    exit 1
  }
}

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

assert_not_contains() {
  local haystack=$1 needle=$2
  if grep -F -- "$needle" <<<"$haystack" >/dev/null; then
    printf 'unexpected text: %s\n' "$needle" >&2
    exit 1
  fi
}

make_workflow() {
  local root=$1 workflow=$2
  local start_users=${3:-1} end_users=${4:-10}
  local duration=${5:-600} ramp=${6:-0}
  local config_authority=${7:-ablfeda} data_authority=${8:-ablfeda}
  local identities=${9:-10} placeholder=${10:-}
  local identity_name=${11:-username}
  local dir="$root/$workflow" i

  mkdir -p "$dir"
  cat >"$dir/scenario.yaml" <<EOF
scenarioName: fixture
startUsers: $start_users
endUsers: $end_users
durationSeconds: $duration
rampDurationSeconds: $ramp
EOF
  cat >"$dir/config.yaml" <<EOF
authority: "$config_authority"
EOF
  {
    printf 'globalDataSets:\n'
    for ((i = 1; i <= 10; i++)); do
      printf '  - params:\n'
      if ((i <= identities)); then
        printf '      - name: %s\n' "$identity_name"
        printf '        value: user%s\n' "$i"
      fi
      printf '      - name: authority\n'
      printf '        value: %s\n' "$data_authority"
    done
    [[ -z "$placeholder" ]] || printf '      - name: marker\n        value: %s\n' "$placeholder"
    printf 'scenarioDataSets: []\n'
  } >"$dir/scenario-data.yaml"
}

make_fake_commands() {
  local fake_bin=$1 fake_log=$2
  mkdir -p "$fake_bin"

  cat >"$fake_bin/id" <<'EOF'
#!/usr/bin/env bash
[[ ${1:-} == -un ]] || exit 2
printf '%s\n' "${FAKE_USER:-opc}"
EOF
  cat >"$fake_bin/hostname" <<'EOF'
#!/usr/bin/env bash
[[ ${1:-} == -s ]] || exit 2
printf '%s\n' "${FAKE_HOSTNAME:-INJABLFEDA001}"
EOF
  cat >"$fake_bin/ps" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ ${1:-} == -p ]] || exit 2
printf 'ps\t%s\n' "$2" >>"$FAKE_LOG"
if [[ -n ${FAKE_LIVE_PID_FILE:-} ]]; then
  grep -Fx -- "$2" "$FAKE_LIVE_PID_FILE" >/dev/null 2>&1
  exit $?
fi
case ${FAKE_PID_LIVE:-auto} in
  1) exit 0 ;;
  0) exit 1 ;;
  auto) kill -0 "$2" 2>/dev/null ;;
  *) exit 2 ;;
esac
EOF
  cat >"$fake_bin/kill-safe" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
signal=TERM
if [[ ${1:-} == -* ]]; then signal=${1#-}; shift; fi
pid=${1:?}
printf 'kill\t%s\t%s\n' "$signal" "$pid" >>"$FAKE_LOG"
if [[ -n ${FAKE_ALLOWED_KILL_FILE:-} ]] && ! grep -Fx -- "$pid" "$FAKE_ALLOWED_KILL_FILE" >/dev/null; then
  printf 'unrelated-kill\t%s\n' "$pid" >>"$FAKE_LOG"
  exit 99
fi
if [[ -n ${FAKE_LIVE_PID_FILE:-} ]]; then
  [[ ${FAKE_KILL_STICKS:-0} == 1 ]] || rm -f -- "$FAKE_LIVE_PID_FILE"
  exit 0
fi
kill "-$signal" "$pid"
EOF
  cat >"$fake_bin/date" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == +%Y%m%d-%H%M%S ]]; then
  printf '%s\n' "${FAKE_BACKUP_TIMESTAMP:-20260811-221500}"
  exit 0
fi
[[ ${1:-} == --iso-8601=seconds ]] || exit 2
counter_file=${FAKE_DATE_COUNTER_FILE:?}
count=0
[[ ! -f "$counter_file" ]] || count=$(<"$counter_file")
((count += 1))
printf '%s\n' "$count" >"$counter_file"
printf '2026-08-11T22:15:%02d-05:00\n' "$count"
EOF
  cat >"$fake_bin/sleep" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'sleep\t%s\n' "$*" >>"$FAKE_LOG"
if [[ ${1:-} != 300 && -n ${FAKE_SLEEP_YIELD:-} ]]; then
  /usr/bin/sleep "$FAKE_SLEEP_YIELD"
fi
if [[ -n ${GATLING_NODE_BATCH_ROOT:-} && -f ${GATLING_NODE_BATCH_ROOT}/gatling-workflow-batch.state ]]; then
  tr '\n' '|' <"${GATLING_NODE_BATCH_ROOT}/gatling-workflow-batch.state" | sed 's/^/state-at-sleep\t/' >>"$FAKE_LOG"
  printf '\n' >>"$FAKE_LOG"
fi
EOF
  cat >"$fake_bin/nohup" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'nohup' >>"$FAKE_LOG"
printf '\t%s' "$@" >>"$FAKE_LOG"
printf '\n' >>"$FAKE_LOG"
exec "$@"
EOF
  cat >"$fake_bin/test-readable" <<'EOF'
#!/usr/bin/env bash
[[ ${1:-} != *"${FAKE_UNREADABLE_SUFFIX:-__never__}" ]]
EOF
  cat >"$fake_bin/sudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ ${1:-} == -n ]] || exit 2
shift
printf 'sudo' >>"$FAKE_LOG"
printf '\t%s' "$@" >>"$FAKE_LOG"
printf '\n' >>"$FAKE_LOG"
[[ ${FAKE_SUDO_FAIL:-0} == 0 ]] || exit 1
if [[ ${FAKE_SUDO_RM_FAIL:-0} == 1 && ${1:-} == rm ]]; then
  exit 1
fi
[[ ${1:-} == true ]] && exit 0
if [[ ${FAKE_SUDO_WRAP_BASH:-0} == 1 && ${1:-} == bash ]]; then
  "$@" &
  child=$!
  printf 'sudo-wrapper\t%s\tchild\t%s\n' "$$" "$child" >>"$FAKE_LOG"
  [[ -z ${FAKE_ALLOWED_KILL_FILE:-} ]] || printf '%s\n%s\n' "$$" "$child" >>"$FAKE_ALLOWED_KILL_FILE"
  wait "$child"
  exit $?
fi
exec "$@"
EOF
  cat >"$fake_bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'docker' >>"$FAKE_LOG"
printf '\t%s' "$@" >>"$FAKE_LOG"
printf '\n' >>"$FAKE_LOG"
[[ ${FAKE_DOCKER_INFO_FAIL:-0} == 0 ]] || { [[ ${1:-} != info ]] || exit 1; }
case "${1:-}" in
  info) exit 0 ;;
  image)
    [[ ${2:-} == inspect && ${3:-} == "$EXPECTED_IMAGE" && ${FAKE_IMAGE_PRESENT:-1} == 1 ]]
    ;;
  network)
    [[ ${2:-} == inspect && ${3:-} == "$EXPECTED_NETWORK" && ${FAKE_NETWORK_PRESENT:-1} == 1 ]]
    ;;
  inspect)
    [[ ${FAKE_EXACT_INSPECT_FAIL:-0} == 0 ]] || exit 1
    case "${4:-}" in
      "$EXPECTED_DNS_CONTAINER")
        if [[ ${3:-} == '{{.State.Running}}' ]]; then
          [[ ${FAKE_DNS_RUNNING:-1} == 1 ]] && printf 'true\n' || printf 'false\n'
        elif [[ ${3:-} == *IPAddress* ]]; then
          printf '%s\n' "${FAKE_DNS_IP:-172.25.0.2}"
        else
          exit 2
        fi
        ;;
      "${FAKE_EXACT_CONTAINER:-__no_active_container__}")
        running=${FAKE_CONTAINER_RUNNING:-0}
        if [[ -n ${FAKE_CONTAINER_STATE_FILE:-} && -f ${FAKE_CONTAINER_STATE_FILE} ]]; then
          running=$(<"$FAKE_CONTAINER_STATE_FILE")
        fi
        [[ $running != error ]] || exit 77
        if [[ ${3:-} == '{{.Name}}|{{.State.Running}}' ]]; then
          printf '/%s|%s\n' "${FAKE_INSPECT_NAME:-${4:-}}" "$running"
        elif [[ ${3:-} == '{{.State.Running}}' ]]; then
          printf '%s\n' "$running"
        else
          exit 2
        fi
        ;;
      *) exit 1 ;;
    esac
    ;;
  stop)
    [[ ${2:-} == "${FAKE_EXACT_CONTAINER:-__no_active_container__}" ]] || exit 9
    if [[ ${FAKE_DOCKER_VERIFY_INSPECT_ERROR:-0} == 1 && -n ${FAKE_CONTAINER_STATE_FILE:-} ]]; then
      printf 'error\n' >"$FAKE_CONTAINER_STATE_FILE"
    elif [[ ${FAKE_DOCKER_STOP_STICKS:-0} != 1 && -n ${FAKE_CONTAINER_STATE_FILE:-} ]]; then
      printf 'false\n' >"$FAKE_CONTAINER_STATE_FILE"
    fi
    ;;
  ps)
    if [[ ${2:-} == -a && ${3:-} == --filter && ${4:-} == name=^/*'$' && ${5:-} == --format && ${6:-} == '{{.Names}}' ]]; then
      [[ ${FAKE_EXACT_PS_A_FAIL:-0} == 0 ]] || exit 1
      [[ ${FAKE_CONTAINER_EXISTS:-1} == 1 ]] && printf '%s\n' "${FAKE_INSPECT_NAME:-${FAKE_EXACT_CONTAINER:-}}"
    elif [[ ${2:-} == --format ]]; then
      [[ ${FAKE_DOCKER_PS_FAIL:-0} == 0 ]] || exit 1
      printf '%s' "${FAKE_RUNNING_CONTAINERS:-}"
    elif [[ ${2:-} == -a && ${3:-} == --format ]]; then
      [[ ${FAKE_DOCKER_PS_A_FAIL:-0} == 0 ]] || exit 1
      printf '%s' "${FAKE_ALL_CONTAINERS:-}"
    else
      exit 2
    fi
    ;;
  run)
    counter_file=${FAKE_DOCKER_RUN_COUNT_FILE:?}
    count=0
    [[ ! -f "$counter_file" ]] || count=$(<"$counter_file")
    ((count += 1))
    printf '%s\n' "$count" >"$counter_file"
    printf 'docker-start\t%s\n' "$count" >>"$FAKE_LOG"
    [[ -z ${FAKE_DOCKER_RUN_DELAY:-} ]] || /usr/bin/sleep "$FAKE_DOCKER_RUN_DELAY"
    summary_var="FAKE_DOCKER_SUMMARY_${count}"
    exit_var="FAKE_DOCKER_EXIT_${count}"
    [[ -z ${!summary_var:-} ]] || printf '%s\n' "${!summary_var}"
    printf 'docker-end\t%s\n' "$count" >>"$FAKE_LOG"
    exit "${!exit_var:-0}"
    ;;
  *) exit 2 ;;
esac
EOF
  chmod +x "$fake_bin"/*
}

run_start() {
  local root=$1 fake_bin=$2 fake_log=$3
  shift 3
  env \
    PATH="$fake_bin:/usr/bin:/bin" \
    GATLING_NODE_BATCH_TEST_MODE=1 \
    GATLING_NODE_BATCH_ROOT="$root" \
    GATLING_NODE_BATCH_READABLE_COMMAND="$fake_bin/test-readable" \
    GATLING_NODE_BATCH_REMOTE_RUNNER_PATH="$remote_script" \
    GATLING_NODE_BATCH_NOHUP_COMMAND="$fake_bin/nohup" \
    GATLING_NODE_BATCH_SUDO_COMMAND="$fake_bin/sudo" \
    GATLING_NODE_BATCH_DOCKER_COMMAND="$fake_bin/docker" \
    GATLING_NODE_BATCH_DATE_COMMAND="$fake_bin/date" \
    GATLING_NODE_BATCH_SLEEP_COMMAND="$fake_bin/sleep" \
    GATLING_NODE_BATCH_PS_COMMAND="$fake_bin/ps" \
    GATLING_NODE_BATCH_KILL_COMMAND="$fake_bin/kill-safe" \
    GATLING_NODE_BATCH_PROC_ROOT="$root/.proc" \
    GATLING_NODE_BATCH_STOP_WAIT_ATTEMPTS="${GATLING_NODE_BATCH_STOP_WAIT_ATTEMPTS:-3}" \
    GATLING_NODE_BATCH_START_WAIT_ATTEMPTS="${GATLING_NODE_BATCH_START_WAIT_ATTEMPTS:-30}" \
    FAKE_SLEEP_YIELD=0.05 \
    FAKE_LOG="$fake_log" \
    EXPECTED_IMAGE='iad.ocir.io/idxlj5etbfyf/gatling_docker:gatling_oci_test' \
    EXPECTED_NETWORK='gatling_dns_mappcernabl010' \
    EXPECTED_DNS_CONTAINER='gatling_dns_mappcernabl010' \
    FAKE_DATE_COUNTER_FILE="$root/.fake-date-count" \
    FAKE_DOCKER_RUN_COUNT_FILE="$root/.fake-docker-count" \
    "$@" bash "$remote_script" start 2>&1
}

run_test_action() {
  local action=$1 root=$2 fake_bin=$3 fake_log=$4
  shift 4
  env \
    PATH="$fake_bin:/usr/bin:/bin" \
    GATLING_NODE_BATCH_TEST_MODE=1 \
    GATLING_NODE_BATCH_ROOT="$root" \
    GATLING_NODE_BATCH_REMOTE_RUNNER_PATH="$remote_script" \
    GATLING_NODE_BATCH_READABLE_COMMAND="$fake_bin/test-readable" \
    GATLING_NODE_BATCH_NOHUP_COMMAND="$fake_bin/nohup" \
    GATLING_NODE_BATCH_SUDO_COMMAND="$fake_bin/sudo" \
    GATLING_NODE_BATCH_DOCKER_COMMAND="$fake_bin/docker" \
    GATLING_NODE_BATCH_DATE_COMMAND="$fake_bin/date" \
    GATLING_NODE_BATCH_SLEEP_COMMAND="$fake_bin/sleep" \
    GATLING_NODE_BATCH_PS_COMMAND="$fake_bin/ps" \
    GATLING_NODE_BATCH_KILL_COMMAND="$fake_bin/kill-safe" \
    GATLING_NODE_BATCH_PROC_ROOT="$root/.proc" \
    GATLING_NODE_BATCH_STOP_WAIT_ATTEMPTS="${GATLING_NODE_BATCH_STOP_WAIT_ATTEMPTS:-3}" \
    FAKE_LOG="$fake_log" \
    FAKE_DATE_COUNTER_FILE="$root/.fake-date-count" \
    FAKE_DOCKER_RUN_COUNT_FILE="$root/.fake-docker-count" \
    EXPECTED_IMAGE='iad.ocir.io/idxlj5etbfyf/gatling_docker:gatling_oci_test' \
    EXPECTED_NETWORK='gatling_dns_mappcernabl010' \
    EXPECTED_DNS_CONTAINER='gatling_dns_mappcernabl010' \
    "$@" bash "$remote_script" "$action" 2>&1
}

assert_preflight_refuses() {
  local label=$1 root=$2 fake_bin=$3 fake_log=$4 expected=$5
  shift 5
  local output status csv="$root/gatling-workflow-results.csv"
  printf 'KEEP_ME\n' >"$csv"
  : >"$fake_log"
  set +e
  output=$(run_start "$root" "$fake_bin" "$fake_log" "$@")
  status=$?
  set -e
  ((status != 0)) || fail "$label unexpectedly succeeded"
  assert_contains "$output" "$expected"
  [[ $(<"$csv") == KEEP_ME ]] || fail "$label moved or replaced the CSV marker"
  if grep -E $'^docker\t(run|stop|rm)([[:space:]]|$)' "$fake_log" >/dev/null; then
    fail "$label invoked a forbidden Docker mutation before rejection"
  fi
  case "$label" in
    wrong-user|wrong-host|sudo-gate|docker-info|image|network|dns-running|dns-ip|live-pid|docker-ps|docker-ps-a|suffix-collision|name-collision) ;;
    *) [[ ! -s "$fake_log" ]] || fail "$label called fake Docker during workflow validation" ;;
  esac
}

skill_root=$(cd "$script_dir/.." && pwd)
remote_script="$skill_root/scripts/gatling_node_batch_remote.sh"
controller="$skill_root/scripts/invoke_gatling_node_batch.ps1"

[[ -f "$remote_script" ]] || { printf 'missing remote script: %s\n' "$remote_script" >&2; exit 1; }
[[ -f "$controller" ]] || { printf 'missing controller script: %s\n' "$controller" >&2; exit 1; }
bash -n "$remote_script"
powershell.exe -NoProfile -Command '& { param([string]$path) $tokens = $null; $errors = $null; [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors); if ($errors.Count -gt 0) { $errors | ForEach-Object { Write-Error $_.Message }; exit 1 } }' "$controller"

controller_text=$(<"$controller")
remote_text=$(<"$remote_script")

if [[ ${GATLING_NODE_BATCH_TEST_FOCUS:-all} == all || ${GATLING_NODE_BATCH_TEST_FOCUS:-all} == controller ]]; then
controller_tmp="$tmp_dir/controller"
capture_dir="$controller_tmp/capture"
mkdir -p "$capture_dir"
capture_win=$(cygpath -w "$capture_dir")

cat >"$controller_tmp/fake-plink.ps1" <<'EOF'
$ErrorActionPreference = 'Stop'
$capture = $env:GATLING_NODE_BATCH_CAPTURE
$countPath = Join-Path $capture 'count.txt'
$count = 0
if (Test-Path -LiteralPath $countPath) {
    $count = [int](Get-Content -LiteralPath $countPath -Raw)
}
$count += 1
[System.IO.File]::WriteAllText($countPath, [string]$count)
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$argumentText = (($args | ForEach-Object { [string]$_ }) -join "`n") + "`n"
[System.IO.File]::WriteAllText((Join-Path $capture "args.$count.txt"), $argumentText, $utf8NoBom)
$stdinText = [Console]::In.ReadToEnd()
[System.IO.File]::WriteAllText((Join-Path $capture "stdin.$count.txt"), $stdinText, $utf8NoBom)
exit 0
EOF
cat >"$controller_tmp/fake-plink.cmd" <<'EOF'
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0fake-plink.ps1" %*
exit /b %ERRORLEVEL%
EOF
fake_plink_win=$(cygpath -w "$controller_tmp/fake-plink.cmd")

reset_controller_capture() {
  rm -f -- "$capture_dir"/*
}

invoke_controller() {
  local action=$1
  GATLING_NODE_BATCH_TEST_MODE=1 \
    GATLING_NODE_BATCH_PLINK="$fake_plink_win" \
    GATLING_NODE_BATCH_CAPTURE="$capture_win" \
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$controller" -Action "$action"
}

assert_controller_args() {
  local actual=$1 command=$2 expected="$controller_tmp/expected-args.txt"
  printf '%s\n' \
    -batch \
    -agent \
    -hostkey \
    'SHA256:MFpjjwtRcQ80ky/fQUoLDozygKyMNNXpBOR90tdj+Pg' \
    'opc@10.44.121.15' \
    "$command" >"$expected"
  tr -d '\r' <"$actual" >"$actual.normalized"
  diff -u "$expected" "$actual.normalized"
}

reset_controller_capture
set +e
invoke_controller 'start;Write-Output INJECTED' >"$controller_tmp/invalid.out" 2>&1
invalid_status=$?
set -e
((invalid_status != 0)) || fail 'invalid controller action unexpectedly succeeded'
[[ ! -e "$capture_dir/count.txt" ]] || fail 'invalid controller action reached Plink'

reset_controller_capture
set +e
override_without_test_mode_output=$(GATLING_NODE_BATCH_PLINK="$fake_plink_win" \
  GATLING_NODE_BATCH_CAPTURE="$capture_win" \
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$controller" -Action status 2>&1)
override_without_test_mode_status=$?
set -e
((override_without_test_mode_status != 0)) || fail 'controller accepted the Plink override without explicit test mode'
assert_contains "$override_without_test_mode_output" 'GATLING_NODE_BATCH_PLINK requires GATLING_NODE_BATCH_TEST_MODE=1'
[[ ! -e "$capture_dir/count.txt" ]] || fail 'override without test mode executed the arbitrary launcher'

reset_controller_capture
invoke_controller start
[[ $(<"$capture_dir/count.txt") == 2 ]] || fail 'start did not invoke Plink exactly twice'
assert_controller_args "$capture_dir/args.1.txt" \
  'sudo -n tee /ablpub/OCI/Torq/Gatling/.gatling-node-batch-runner.remote.sh >/dev/null && sudo -n chmod 700 /ablpub/OCI/Torq/Gatling/.gatling-node-batch-runner.remote.sh'
assert_controller_args "$capture_dir/args.2.txt" \
  'bash /ablpub/OCI/Torq/Gatling/.gatling-node-batch-runner.remote.sh start'
tr -d '\r' <"$capture_dir/stdin.1.txt" >"$controller_tmp/start-stdin.normalized"
cmp -s "$remote_script" "$controller_tmp/start-stdin.normalized" || fail 'start deployment did not stream the exact remote script body'
[[ ! -s "$capture_dir/stdin.2.txt" ]] || fail 'start action invocation unexpectedly streamed input'

for action in status stop; do
  reset_controller_capture
  invoke_controller "$action"
  [[ $(<"$capture_dir/count.txt") == 1 ]] || fail "$action did not invoke Plink exactly once"
  assert_controller_args "$capture_dir/args.1.txt" "bash -s -- $action"
  tr -d '\r' <"$capture_dir/stdin.1.txt" >"$controller_tmp/$action-stdin.normalized"
  cmp -s "$remote_script" "$controller_tmp/$action-stdin.normalized" || fail "$action did not stream the exact remote script body"
  action_args=$(<"$capture_dir/args.1.txt")
  assert_not_contains "$action_args" 'tee'
  assert_not_contains "$action_args" 'chmod'
  assert_not_contains "$action_args" '.gatling-node-batch-runner.remote.sh'
done

captured_args=$(find "$capture_dir" -name 'args.*.txt' | sort | xargs cat)
for forbidden in '-pw' '-pwfile' '-i' 'StrictHostKeyChecking=no' '-host-ca' '-no-hostkey' 'acceptnew'; do
  assert_not_contains "$captured_args" "$forbidden"
done
assert_not_contains "$(find "$capture_dir" -name 'stdin.*.txt' | sort | xargs cat)" 'PRIVATE KEY'
fi

assert_contains "$remote_text" 'workflow_name,begin_time,end_time,ok_count,ko_count'
assert_contains "$remote_text" 'startUsers'
assert_contains "$remote_text" 'endUsers'
assert_contains "$remote_text" 'durationSeconds'
assert_contains "$remote_text" 'rampDurationSeconds'
assert_contains "$remote_text" 'ablfeda'
assert_contains "$remote_text" '300'
assert_contains "$remote_text" 'iad.ocir.io/idxlj5etbfyf/gatling_docker:gatling_oci_test'
assert_contains "$remote_text" 'gatling_dns_mappcernabl010'
assert_contains "$remote_text" 'mappcernabl010'
assert_contains "$remote_text" '172.25.0.2'

fixtures="$tmp_dir/fixtures"
fake_bin="$tmp_dir/fake-bin"
fake_log="$tmp_dir/fake.log"
mkdir -p "$fixtures"
make_fake_commands "$fake_bin" "$fake_log"

if [[ ${GATLING_NODE_BATCH_TEST_FOCUS:-all} == all || ${GATLING_NODE_BATCH_TEST_FOCUS:-all} == preflight ]]; then
# A legitimate parameter named authority may contain prepared MillDomain data.
make_workflow "$fixtures" z-valid 1 10 600 0 ablfeda MillDomain 10 '' username_A
make_workflow "$fixtures" a-valid 1 10 600 0 ablfeda ablfeda 10 '' user_id_SBO
mkdir "$fixtures/docs"
: >"$fake_log"
valid_output=$(run_start "$fixtures" "$fake_bin" "$fake_log" GATLING_NODE_BATCH_PREFLIGHT_ONLY=1)
assert_contains "$valid_output" 'SKIPPED workflow=docs file=required-yaml key=readable expected=config.yaml,scenario.yaml,scenario-data.yaml actual=missing-or-unreadable'
assert_contains "$valid_output" 'a-valid'
assert_contains "$valid_output" 'z-valid'
[[ $(grep -c '^a-valid$' <<<"$valid_output") -eq 1 ]] || fail 'a-valid was not selected exactly once'
[[ $(grep -c '^z-valid$' <<<"$valid_output") -eq 1 ]] || fail 'z-valid was not selected exactly once'
[[ $(grep -n -E '^(a-valid|z-valid)$' <<<"$valid_output" | cut -d: -f2 | paste -sd, -) == a-valid,z-valid ]] || fail 'workflows were not sorted'
assert_not_contains "$valid_output" 'MillDomain'

for case_name in sequence-start sequence-end sequence-authority start-zero end-nine duration-601 ramp-one config-authority data-authority comment-only-authority comment-only-authority-param change-me replace-me nine-identities; do
  case_root="$tmp_dir/$case_name"
  mkdir -p "$case_root"
  case "$case_name" in
    sequence-start) make_workflow "$case_root" bad; printf '%s\n' '- startUsers: 0' >>"$case_root/bad/scenario.yaml"; expected='workflow=bad file=scenario.yaml key=startUsers expected=1 actual=0' ;;
    sequence-end) make_workflow "$case_root" bad; printf '%s\n' '- endUsers: 9' >>"$case_root/bad/scenario.yaml"; expected='workflow=bad file=scenario.yaml key=endUsers expected=10 actual=9' ;;
    sequence-authority) make_workflow "$case_root" bad; sed '/scenarioDataSets:/i\  - authority: wrong' "$case_root/bad/scenario-data.yaml" >"$case_root/bad/scenario-data.next"; mv "$case_root/bad/scenario-data.next" "$case_root/bad/scenario-data.yaml"; expected='workflow=bad file=scenario-data.yaml key=authority expected=ablfeda actual=wrong' ;;
    start-zero) make_workflow "$case_root" bad 0; expected='workflow=bad file=scenario.yaml key=startUsers expected=1 actual=0' ;;
    end-nine) make_workflow "$case_root" bad 1 9; expected='workflow=bad file=scenario.yaml key=endUsers expected=10 actual=9' ;;
    duration-601) make_workflow "$case_root" bad 1 10 601; expected='workflow=bad file=scenario.yaml key=durationSeconds expected=600 actual=601' ;;
    ramp-one) make_workflow "$case_root" bad 1 10 600 1; expected='workflow=bad file=scenario.yaml key=rampDurationSeconds expected=0 actual=1' ;;
    config-authority) make_workflow "$case_root" bad 1 10 600 0 wrong; expected='workflow=bad file=config.yaml key=authority expected=ablfeda actual=wrong' ;;
    data-authority) make_workflow "$case_root" bad 1 10 600 0 ablfeda ablfeda; printf 'authority: wrong\n' >>"$case_root/bad/scenario-data.yaml"; expected='workflow=bad file=scenario-data.yaml key=authority expected=ablfeda actual=wrong' ;;
    comment-only-authority) make_workflow "$case_root" bad; printf 'authority: # intentionally blank\n' >"$case_root/bad/config.yaml"; expected='workflow=bad file=config.yaml key=authority expected=ablfeda actual=<blank>' ;;
    comment-only-authority-param) make_workflow "$case_root" bad; sed '0,/value: ablfeda/s//value: # intentionally blank/' "$case_root/bad/scenario-data.yaml" >"$case_root/bad/scenario-data.next"; mv "$case_root/bad/scenario-data.next" "$case_root/bad/scenario-data.yaml"; expected='workflow=bad file=scenario-data.yaml key=authority-parameter expected=nonblank actual=<blank>' ;;
    change-me) make_workflow "$case_root" bad 1 10 600 0 ablfeda ablfeda 10 Change_Me; expected='workflow=bad file=scenario-data.yaml key=placeholder expected=absent actual=Change_Me' ;;
    replace-me) make_workflow "$case_root" bad 1 10 600 0 ablfeda ablfeda 10 REPLACE_ME; expected='workflow=bad file=scenario-data.yaml key=placeholder expected=absent actual=REPLACE_ME' ;;
    nine-identities) make_workflow "$case_root" bad 1 10 600 0 ablfeda ablfeda 9; expected='workflow=bad file=scenario-data.yaml key=identity-records expected=>=10 actual=9' ;;
  esac
  assert_preflight_refuses "$case_name" "$case_root" "$fake_bin" "$fake_log" "$expected"
done

unreadable_root="$tmp_dir/unreadable"
mkdir -p "$unreadable_root"
make_workflow "$unreadable_root" bad
assert_preflight_refuses unreadable "$unreadable_root" "$fake_bin" "$fake_log" \
  'workflow=bad file=scenario.yaml key=readable expected=true actual=false' \
  FAKE_UNREADABLE_SUFFIX='/bad/scenario.yaml'

unsafe_root="$tmp_dir/unsafe"
mkdir -p "$unsafe_root"
make_workflow "$unsafe_root" 'bad name'
assert_preflight_refuses unsafe-name "$unsafe_root" "$fake_bin" "$fake_log" \
  'workflow=bad name file=directory key=basename expected=^[A-Za-z0-9][A-Za-z0-9_.-]*$ actual=bad name'

runtime_root="$tmp_dir/runtime"
mkdir -p "$runtime_root"
make_workflow "$runtime_root" good 1 10 600 0 ablfeda ablfeda 10 '' personnel_idWest
assert_preflight_refuses wrong-user "$runtime_root" "$fake_bin" "$fake_log" \
  'workflow=runtime file=host key=user expected=opc actual=root' FAKE_USER=root
assert_preflight_refuses wrong-host "$runtime_root" "$fake_bin" "$fake_log" \
  'workflow=runtime file=host key=hostname expected=INJABLFEDA001 actual=OTHER' FAKE_HOSTNAME=OTHER
assert_preflight_refuses sudo-gate "$runtime_root" "$fake_bin" "$fake_log" \
  'workflow=runtime file=docker key=sudo expected=noninteractive actual=failed' FAKE_SUDO_FAIL=1
assert_preflight_refuses docker-info "$runtime_root" "$fake_bin" "$fake_log" \
  'workflow=runtime file=docker key=info expected=available actual=failed' FAKE_DOCKER_INFO_FAIL=1
assert_preflight_refuses docker-ps "$runtime_root" "$fake_bin" "$fake_log" \
  'workflow=runtime file=docker key=ps expected=available actual=failed' FAKE_DOCKER_PS_FAIL=1
assert_preflight_refuses docker-ps-a "$runtime_root" "$fake_bin" "$fake_log" \
  'workflow=runtime file=docker key=ps-a expected=available actual=failed' FAKE_DOCKER_PS_A_FAIL=1
assert_preflight_refuses image "$runtime_root" "$fake_bin" "$fake_log" \
  'workflow=runtime file=docker key=image expected=iad.ocir.io/idxlj5etbfyf/gatling_docker:gatling_oci_test actual=missing' FAKE_IMAGE_PRESENT=0
assert_preflight_refuses network "$runtime_root" "$fake_bin" "$fake_log" \
  'workflow=runtime file=docker key=network expected=gatling_dns_mappcernabl010 actual=missing' FAKE_NETWORK_PRESENT=0
assert_preflight_refuses dns-running "$runtime_root" "$fake_bin" "$fake_log" \
  'workflow=runtime file=docker key=dns-running expected=true actual=false' FAKE_DNS_RUNNING=0
assert_preflight_refuses dns-ip "$runtime_root" "$fake_bin" "$fake_log" \
  'workflow=runtime file=docker key=dns-ip expected=172.25.0.2 actual=172.25.0.9' FAKE_DNS_IP=172.25.0.9
printf '4242\n' >"$runtime_root/gatling-workflow-batch.pid"
assert_preflight_refuses live-pid "$runtime_root" "$fake_bin" "$fake_log" \
  'workflow=runtime file=gatling-workflow-batch.pid key=owned-pid expected=not-live actual=4242' FAKE_PID_LIVE=1
rm "$runtime_root/gatling-workflow-batch.pid"
assert_preflight_refuses suffix-collision "$runtime_root" "$fake_bin" "$fake_log" \
  'workflow=runtime file=docker key=running-suffix expected=none actual=other_mappcernabl010' \
  $'FAKE_RUNNING_CONTAINERS=gatling_dns_mappcernabl010\nother_mappcernabl010\n'
assert_preflight_refuses name-collision "$runtime_root" "$fake_bin" "$fake_log" \
  'workflow=good file=docker key=container-name expected=absent actual=good_mappcernabl010' \
  $'FAKE_ALL_CONTAINERS=good_mappcernabl010\n'
fi

if [[ ${GATLING_NODE_BATCH_TEST_FOCUS:-all} == all || ${GATLING_NODE_BATCH_TEST_FOCUS:-all} == execution ]]; then
# A new run preserves the prior CSV without overwriting an existing backup.
execution_root="$tmp_dir/execution"
mkdir -p "$execution_root"
make_workflow "$execution_root" z-second
make_workflow "$execution_root" a-first
printf 'OLD_RESULTS\n' >"$execution_root/gatling-workflow-results.csv"
printf 'OLDER_BACKUP\n' >"$execution_root/gatling-workflow-results.backup-20260811-221500.csv"
: >"$fake_log"
initialize_output=$(run_test_action __test_initialize "$execution_root" "$fake_bin" "$fake_log")
assert_contains "$initialize_output" "CSV_PATH=$execution_root/gatling-workflow-results.csv"
assert_contains "$initialize_output" "BACKUP_PATH=$execution_root/gatling-workflow-results.backup-20260811-221500-1.csv"
[[ $(<"$execution_root/gatling-workflow-results.backup-20260811-221500.csv") == OLDER_BACKUP ]] || fail 'existing backup was overwritten'
[[ $(<"$execution_root/gatling-workflow-results.backup-20260811-221500-1.csv") == OLD_RESULTS ]] || fail 'old CSV was not moved to collision-safe backup'
[[ $(<"$execution_root/gatling-workflow-results.csv") == 'workflow_name,begin_time,end_time,ok_count,ko_count' ]] || fail 'canonical CSV header is not exact'

# The direct worker hook exercises production sequencing without a detached-process race.
: >"$fake_log"
worker_output=$(run_test_action __test_worker "$execution_root" "$fake_bin" "$fake_log" \
  FAKE_DOCKER_EXIT_1=17 \
  $'FAKE_DOCKER_SUMMARY_1=> Global                                                   (not a valid summary)' \
  $'FAKE_DOCKER_SUMMARY_2=> Global                                                   (OK=19     KO=2     )\nnoise\n> Global                                                   (OK=20     KO=1     )')
[[ -z "$worker_output" ]] || fail "worker emitted unexpected output: $worker_output"
mapfile -t csv_lines <"$execution_root/gatling-workflow-results.csv"
[[ ${#csv_lines[@]} -eq 3 ]] || fail "expected header plus two rows, got ${#csv_lines[@]}"
[[ ${csv_lines[0]} == 'workflow_name,begin_time,end_time,ok_count,ko_count' ]] || fail 'worker changed CSV header'
[[ ${csv_lines[1]} == 'a-first,2026-08-11T22:15:01-05:00,2026-08-11T22:15:02-05:00,UNKNOWN,UNKNOWN' ]] || fail "unexpected first CSV row: ${csv_lines[1]}"
[[ ${csv_lines[2]} == 'z-second,2026-08-11T22:15:03-05:00,2026-08-11T22:15:04-05:00,20,1' ]] || fail "unexpected second CSV row: ${csv_lines[2]}"

expected_first=$'docker\trun\t--rm\t--log-opt\tmax-size=10m\t--log-opt\tmax-file=3\t--network\tgatling_dns_mappcernabl010\t--dns\t172.25.0.2\t--name\ta-first_mappcernabl010\t-e\tMAVEN_GOAL=gatling-crank:crank\t-e\tMAVEN_OFFLINE=true\t-e\tGATLING_MAX_HEAP=4g\t-v\t'"$execution_root"$'/a-first:/gatling/dataDirectory\t-v\t'"$execution_root"$'/a-first/Report:/gatling/results\tiad.ocir.io/idxlj5etbfyf/gatling_docker:gatling_oci_test'
expected_second=${expected_first//a-first/z-second}
grep -Fx -- "$expected_first" "$fake_log" >/dev/null || fail 'first Docker argument vector was not exact'
grep -Fx -- "$expected_second" "$fake_log" >/dev/null || fail 'second Docker argument vector was not exact'
event_order=$(grep -E $'^(docker-start|docker-end|sleep)\t' "$fake_log" | paste -sd, -)
[[ "$event_order" == $'docker-start\t1,docker-end\t1,sleep\t300,docker-start\t2,docker-end\t2' ]] || fail "incorrect sequential event order: $event_order"
[[ $(grep -c $'^sleep\t300$' "$fake_log") -eq 1 ]] || fail 'cooldown count was not exactly one'
assert_file_contains "$fake_log" $'state-at-sleep\tphase=COOLDOWN|workflow=a-first|container=a-first_mappcernabl010|completed=1|total=2|'
[[ ! -e "$execution_root/gatling-workflow-batch.pid" ]] || fail 'normal completion left PID file behind'
[[ ! -e "$execution_root/gatling-workflow-batch.state" ]] || fail 'normal completion left state file behind'

# Production-shaped sudo supervises a distinct Bash worker. The worker, not
# the launcher wrapper, must publish the PID reported by start.
start_root="$tmp_dir/start-supervised"
mkdir -p "$start_root"
make_workflow "$start_root" only-workflow
: >"$fake_log"
: >"$start_root/.allowed-kills"
start_output=$(run_start "$start_root" "$fake_bin" "$fake_log" \
  FAKE_SUDO_WRAP_BASH=1 FAKE_DOCKER_RUN_DELAY=1 \
  FAKE_ALLOWED_KILL_FILE="$start_root/.allowed-kills")
assert_contains "$start_output" 'BATCH_STATE=STARTED'
reported_worker=$(sed -n 's/^WORKER_PID=//p' <<<"$start_output")
wrapper_pid=$(awk -F '\t' '$1=="sudo-wrapper" {print $2; exit}' "$fake_log")
child_pid=$(awk -F '\t' '$1=="sudo-wrapper" {print $4; exit}' "$fake_log")
[[ "$reported_worker" == "$child_pid" ]] || fail "start reported launcher PID $reported_worker instead of worker PID $child_pid"
[[ "$reported_worker" != "$wrapper_pid" ]] || fail 'production-shaped wrapper and worker PID did not differ'
assert_not_contains "$(<"$fake_log")" 'unrelated-kill'

# A launcher/worker that exits before publishing RUNNING must not leave stale
# ownership files or kill any PID outside the launched chain.
exit_runner="$tmp_dir/exit-before-state.sh"
cat >"$exit_runner" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$$" >"$GATLING_NODE_BATCH_ROOT/gatling-workflow-batch.pid"
exit 23
EOF
chmod +x "$exit_runner"
failure_root="$tmp_dir/failure-exit"
mkdir -p "$failure_root"
make_workflow "$failure_root" only-workflow
: >"$fake_log"
: >"$failure_root/.allowed-kills"
set +e
failure_output=$(run_start "$failure_root" "$fake_bin" "$fake_log" \
  GATLING_NODE_BATCH_REMOTE_RUNNER_PATH="$exit_runner" FAKE_SUDO_WRAP_BASH=1 \
  FAKE_ALLOWED_KILL_FILE="$failure_root/.allowed-kills")
failure_status=$?
set -e
((failure_status != 0)) || fail 'exit-before-state start unexpectedly succeeded'
assert_contains "$failure_output" 'reason=worker-exited-before-state'
[[ ! -e "$failure_root/gatling-workflow-batch.pid" ]] || fail 'exit-before-state left PID file'
[[ ! -e "$failure_root/gatling-workflow-batch.state" ]] || fail 'exit-before-state left state file'
assert_not_contains "$(<"$fake_log")" 'unrelated-kill'

# A live worker that never establishes state must be terminated and reaped.
timeout_runner="$tmp_dir/timeout-before-state.sh"
cat >"$timeout_runner" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$$" >"$GATLING_NODE_BATCH_ROOT/gatling-workflow-batch.pid"
trap 'exit 0' TERM INT HUP
/usr/bin/sleep 30 &
wait $!
EOF
chmod +x "$timeout_runner"
timeout_root="$tmp_dir/failure-timeout"
mkdir -p "$timeout_root"
make_workflow "$timeout_root" only-workflow
: >"$fake_log"
: >"$timeout_root/.allowed-kills"
set +e
timeout_output=$(run_start "$timeout_root" "$fake_bin" "$fake_log" \
  GATLING_NODE_BATCH_REMOTE_RUNNER_PATH="$timeout_runner" FAKE_SUDO_WRAP_BASH=1 \
  GATLING_NODE_BATCH_START_WAIT_ATTEMPTS=3 \
  FAKE_ALLOWED_KILL_FILE="$timeout_root/.allowed-kills")
timeout_status=$?
set -e
((timeout_status != 0)) || fail 'state-timeout start unexpectedly succeeded'
assert_contains "$timeout_output" 'reason=state-timeout'
[[ ! -e "$timeout_root/gatling-workflow-batch.pid" ]] || fail 'state-timeout left PID file'
[[ ! -e "$timeout_root/gatling-workflow-batch.state" ]] || fail 'state-timeout left state file'
assert_not_contains "$(<"$fake_log")" 'unrelated-kill'
[[ $(grep -c $'^kill\t' "$fake_log") -ge 1 ]] || fail 'state-timeout did not terminate its worker chain'
fi

if [[ ${GATLING_NODE_BATCH_TEST_FOCUS:-all} == all || ${GATLING_NODE_BATCH_TEST_FOCUS:-all} == lifecycle ]]; then
write_lifecycle_state() {
  local root=$1 phase=$2 workflow=$3 container=$4 completed=$5 total=$6
  printf 'phase=%s\nworkflow=%s\ncontainer=%s\ncompleted=%s\ntotal=%s\n' \
    "$phase" "$workflow" "$container" "$completed" "$total" \
    >"$root/gatling-workflow-batch.state"
}

make_fake_process() {
  local root=$1 pid=$2
  shift 2
  mkdir -p "$root/.proc/$pid"
  printf '%s\0' "$@" >"$root/.proc/$pid/cmdline"
}

owned_command=(bash /ablpub/OCI/Torq/Gatling/.gatling-node-batch-runner.remote.sh __worker)

# RUNNING status reports exact ownership, state, progress, and the latest five
# result rows, while leaving every lifecycle artifact untouched.
status_running_root="$tmp_dir/status-running"
mkdir -p "$status_running_root"
printf '4242\n' >"$status_running_root/gatling-workflow-batch.pid"
write_lifecycle_state "$status_running_root" RUNNING alpha alpha_mappcernabl010 7 8
make_fake_process "$status_running_root" 4242 "${owned_command[@]}"
printf '4242\n' >"$status_running_root/.live-pid"
printf 'true\n' >"$status_running_root/.container-state"
{
  printf '%s\n' 'workflow_name,begin_time,end_time,ok_count,ko_count'
  for i in 1 2 3 4 5 6 7; do printf 'workflow-%s,begin-%s,end-%s,%s,0\n' "$i" "$i" "$i" "$i"; done
} >"$status_running_root/gatling-workflow-results.csv"
cp "$status_running_root/gatling-workflow-batch.pid" "$status_running_root/.pid.before"
cp "$status_running_root/gatling-workflow-batch.state" "$status_running_root/.state.before"
cp "$status_running_root/gatling-workflow-results.csv" "$status_running_root/.csv.before"
: >"$fake_log"
status_output=$(run_test_action status "$status_running_root" "$fake_bin" "$fake_log" \
  FAKE_LIVE_PID_FILE="$status_running_root/.live-pid" \
  FAKE_EXACT_CONTAINER=alpha_mappcernabl010 \
  FAKE_CONTAINER_STATE_FILE="$status_running_root/.container-state")
assert_contains "$status_output" 'BATCH_STATE=RUNNING'
assert_contains "$status_output" 'WORKER_PID=4242'
assert_contains "$status_output" 'PROCESS_COMMAND=bash /ablpub/OCI/Torq/Gatling/.gatling-node-batch-runner.remote.sh __worker'
assert_contains "$status_output" 'ACTIVE_WORKFLOW=alpha'
assert_contains "$status_output" 'ACTIVE_CONTAINER=alpha_mappcernabl010'
assert_contains "$status_output" 'COMPLETED=7'
assert_contains "$status_output" 'TOTAL=8'
assert_contains "$status_output" 'workflow_name,begin_time,end_time,ok_count,ko_count'
for i in 3 4 5 6 7; do assert_contains "$status_output" "workflow-$i,begin-$i,end-$i,$i,0"; done
assert_not_contains "$status_output" 'workflow-2,begin-2,end-2,2,0'
cmp -s "$status_running_root/.pid.before" "$status_running_root/gatling-workflow-batch.pid" || fail 'status changed PID file'
cmp -s "$status_running_root/.state.before" "$status_running_root/gatling-workflow-batch.state" || fail 'status changed state file'
cmp -s "$status_running_root/.csv.before" "$status_running_root/gatling-workflow-results.csv" || fail 'status changed CSV file'
[[ $(grep -c $'^docker\tps\t-a\t--filter\tname=\^/alpha_mappcernabl010\$\t--format\t{{.Names}}$' "$fake_log") -eq 1 ]] || fail 'status did not enumerate only the exact state container'
[[ $(grep -c $'^docker\tinspect\t-f\t{{.State.Running}}\talpha_mappcernabl010$' "$fake_log") -eq 1 ]] || fail 'status did not inspect only the exact state container'

status_cooldown_root="$tmp_dir/status-cooldown"
mkdir -p "$status_cooldown_root"
printf '4343\n' >"$status_cooldown_root/gatling-workflow-batch.pid"
write_lifecycle_state "$status_cooldown_root" COOLDOWN alpha alpha_mappcernabl010 3 8
make_fake_process "$status_cooldown_root" 4343 "${owned_command[@]}"
printf '4343\n' >"$status_cooldown_root/.live-pid"
printf 'false\n' >"$status_cooldown_root/.container-state"
printf '%s\none,b,e,1,0\ntwo,b,e,1,0\nthree,b,e,1,0\n' \
  'workflow_name,begin_time,end_time,ok_count,ko_count' \
  >"$status_cooldown_root/gatling-workflow-results.csv"
: >"$fake_log"
cooldown_output=$(run_test_action status "$status_cooldown_root" "$fake_bin" "$fake_log" \
  FAKE_LIVE_PID_FILE="$status_cooldown_root/.live-pid" \
  FAKE_EXACT_CONTAINER=alpha_mappcernabl010 \
  FAKE_CONTAINER_STATE_FILE="$status_cooldown_root/.container-state")
assert_contains "$cooldown_output" 'BATCH_STATE=COOLDOWN'

status_completed_root="$tmp_dir/status-completed"
mkdir -p "$status_completed_root"
printf '%s\nalpha,b,e,10,0\n' 'workflow_name,begin_time,end_time,ok_count,ko_count' >"$status_completed_root/gatling-workflow-results.csv"
completed_output=$(run_test_action status "$status_completed_root" "$fake_bin" "$fake_log")
assert_contains "$completed_output" 'BATCH_STATE=COMPLETED'
assert_contains "$completed_output" 'COMPLETED=1'
assert_contains "$completed_output" 'TOTAL=1'
[[ $(grep -c '^workflow_name,begin_time,end_time,ok_count,ko_count$' <<<"$completed_output") -eq 1 ]] || fail 'completed status duplicated the CSV header'

status_empty_root="$tmp_dir/status-empty"
mkdir -p "$status_empty_root"
empty_output=$(run_test_action status "$status_empty_root" "$fake_bin" "$fake_log")
assert_contains "$empty_output" 'BATCH_STATE=NOT_STARTED'

for stale_case in dead mismatched orphan; do
  stale_root="$tmp_dir/status-stale-$stale_case"
  mkdir -p "$stale_root"
  write_lifecycle_state "$stale_root" RUNNING alpha alpha_mappcernabl010 0 1
  cp "$stale_root/gatling-workflow-batch.state" "$stale_root/.state.before"
  if [[ $stale_case != orphan ]]; then
    printf '4545\n' >"$stale_root/gatling-workflow-batch.pid"
    cp "$stale_root/gatling-workflow-batch.pid" "$stale_root/.pid.before"
    if [[ $stale_case == mismatched ]]; then
      make_fake_process "$stale_root" 4545 bash /tmp/not-the-runner __worker
      printf '4545\n' >"$stale_root/.live-pid"
    fi
  fi
  stale_output=$(run_test_action status "$stale_root" "$fake_bin" "$fake_log" \
    FAKE_LIVE_PID_FILE="$stale_root/.live-pid" FAKE_EXACT_CONTAINER=alpha_mappcernabl010)
  assert_contains "$stale_output" 'BATCH_STATE=STALE_STATE'
  cmp -s "$stale_root/.state.before" "$stale_root/gatling-workflow-batch.state" || fail "$stale_case status changed state file"
  if [[ $stale_case != orphan ]]; then
    cmp -s "$stale_root/.pid.before" "$stale_root/gatling-workflow-batch.pid" || fail "$stale_case status changed PID file"
  fi
done

for refusal in missing-pid nonnumeric-pid wrong-command wrong-state-container dns-container mismatched-running-container ps-a-error inspect-error; do
  stop_root="$tmp_dir/stop-$refusal"
  mkdir -p "$stop_root"
  workflow=alpha
  container=alpha_mappcernabl010
  pid=4646
  [[ $refusal != dns-container ]] || { workflow=gatling_dns; container=gatling_dns_mappcernabl010; }
  [[ $refusal != wrong-state-container ]] || container=unrelated_mappcernabl010
  write_lifecycle_state "$stop_root" RUNNING "$workflow" "$container" 0 1
  if [[ $refusal != missing-pid ]]; then
    [[ $refusal != nonnumeric-pid ]] && printf '%s\n' "$pid" >"$stop_root/gatling-workflow-batch.pid" || printf 'not-a-pid\n' >"$stop_root/gatling-workflow-batch.pid"
  fi
  if [[ $refusal != missing-pid && $refusal != nonnumeric-pid ]]; then
    [[ $refusal == wrong-command ]] && make_fake_process "$stop_root" "$pid" bash /tmp/not-the-runner __worker || make_fake_process "$stop_root" "$pid" "${owned_command[@]}"
    printf '%s\n' "$pid" >"$stop_root/.live-pid"
  fi
  cp "$stop_root/gatling-workflow-batch.state" "$stop_root/.state.before"
  [[ ! -f "$stop_root/gatling-workflow-batch.pid" ]] || cp "$stop_root/gatling-workflow-batch.pid" "$stop_root/.pid.before"
  [[ $refusal == inspect-error ]] && printf 'error\n' >"$stop_root/.container-state" || printf 'true\n' >"$stop_root/.container-state"
  inspect_name=$container
  [[ $refusal != mismatched-running-container ]] || inspect_name=other_mappcernabl010
  : >"$fake_log"
  set +e
  refusal_output=$(run_test_action stop "$stop_root" "$fake_bin" "$fake_log" \
    FAKE_LIVE_PID_FILE="$stop_root/.live-pid" \
    FAKE_EXACT_CONTAINER="$container" FAKE_INSPECT_NAME="$inspect_name" \
    FAKE_CONTAINER_STATE_FILE="$stop_root/.container-state" \
    FAKE_EXACT_PS_A_FAIL="$([[ $refusal == ps-a-error ]] && printf 1 || printf 0)" \
    FAKE_EXACT_INSPECT_FAIL="$([[ $refusal == inspect-error ]] && printf 1 || printf 0)")
  refusal_status=$?
  set -e
  ((refusal_status != 0)) || fail "$refusal stop unexpectedly succeeded"
  assert_contains "$refusal_output" 'BATCH_STATE=STOP_REFUSED'
  cmp -s "$stop_root/.state.before" "$stop_root/gatling-workflow-batch.state" || fail "$refusal changed state file"
  if [[ -f "$stop_root/.pid.before" ]]; then
    cmp -s "$stop_root/.pid.before" "$stop_root/gatling-workflow-batch.pid" || fail "$refusal changed PID file"
  fi
  ! grep -E $'^(docker\tstop|kill\t)' "$fake_log" >/dev/null || fail "$refusal performed a mutation"
done

stop_root="$tmp_dir/stop-valid"
mkdir -p "$stop_root"
printf '4747\n' >"$stop_root/gatling-workflow-batch.pid"
write_lifecycle_state "$stop_root" RUNNING alpha alpha_mappcernabl010 0 1
make_fake_process "$stop_root" 4747 "${owned_command[@]}"
printf '4747\n' >"$stop_root/.live-pid"
printf 'true\n' >"$stop_root/.container-state"
: >"$fake_log"
stop_output=$(run_test_action stop "$stop_root" "$fake_bin" "$fake_log" \
  FAKE_LIVE_PID_FILE="$stop_root/.live-pid" FAKE_ALLOWED_KILL_FILE="$stop_root/.live-pid" \
  FAKE_EXACT_CONTAINER=alpha_mappcernabl010 FAKE_CONTAINER_STATE_FILE="$stop_root/.container-state")
assert_contains "$stop_output" 'BATCH_STATE=STOPPED'
[[ ! -e "$stop_root/gatling-workflow-batch.pid" ]] || fail 'successful stop left PID file'
[[ ! -e "$stop_root/gatling-workflow-batch.state" ]] || fail 'successful stop left state file'
stop_line=$(grep -n $'^docker\tstop\talpha_mappcernabl010$' "$fake_log" | cut -d: -f1)
kill_line=$(grep -n $'^kill\tTERM\t4747$' "$fake_log" | cut -d: -f1)
last_ps_line=$(grep -n $'^ps\t4747$' "$fake_log" | tail -n 1 | cut -d: -f1)
last_inspect_line=$(grep -n $'^docker\tinspect\t-f\t{{.State.Running}}\talpha_mappcernabl010$' "$fake_log" | tail -n 1 | cut -d: -f1)
cleanup_line=$(grep -n $'^sudo\trm\t-f\t--\t.*/gatling-workflow-batch.pid\t.*/gatling-workflow-batch.state$' "$fake_log" | cut -d: -f1 || true)
[[ -n $stop_line && -n $kill_line && -n $last_ps_line && -n $last_inspect_line && -n $cleanup_line ]] || fail 'successful stop missed an exact lifecycle operation'
((stop_line < kill_line && kill_line < last_ps_line && kill_line < last_inspect_line)) || fail 'stop/TERM/verification order was not exact'
((last_ps_line < cleanup_line && last_inspect_line < cleanup_line)) || fail 'sudo cleanup happened before absence verification'

# Cleanup is a privileged operation because the worker creates both ownership
# files as root. A cleanup failure is reported and cannot be called STOPPED.
cleanup_fail_root="$tmp_dir/stop-cleanup-failed"
mkdir -p "$cleanup_fail_root"
printf '4757\n' >"$cleanup_fail_root/gatling-workflow-batch.pid"
write_lifecycle_state "$cleanup_fail_root" RUNNING alpha alpha_mappcernabl010 0 1
make_fake_process "$cleanup_fail_root" 4757 "${owned_command[@]}"
printf '4757\n' >"$cleanup_fail_root/.live-pid"
printf 'true\n' >"$cleanup_fail_root/.container-state"
: >"$fake_log"
set +e
cleanup_fail_output=$(run_test_action stop "$cleanup_fail_root" "$fake_bin" "$fake_log" \
  FAKE_LIVE_PID_FILE="$cleanup_fail_root/.live-pid" FAKE_ALLOWED_KILL_FILE="$cleanup_fail_root/.live-pid" \
  FAKE_EXACT_CONTAINER=alpha_mappcernabl010 FAKE_CONTAINER_STATE_FILE="$cleanup_fail_root/.container-state" \
  FAKE_SUDO_RM_FAIL=1)
cleanup_fail_status=$?
set -e
((cleanup_fail_status != 0)) || fail 'stop succeeded after privileged cleanup failed'
assert_contains "$cleanup_fail_output" 'BATCH_STATE=STOP_FAILED reason=cleanup-failed'
assert_not_contains "$cleanup_fail_output" 'BATCH_STATE=STOPPED'
[[ -f "$cleanup_fail_root/gatling-workflow-batch.pid" && -f "$cleanup_fail_root/gatling-workflow-batch.state" ]] || fail 'cleanup failure unexpectedly removed ownership files'
grep -E $'^sudo\trm\t-f\t--\t.*/gatling-workflow-batch.pid\t.*/gatling-workflow-batch.state$' "$fake_log" >/dev/null || fail 'cleanup failure did not use the exact sudo-mediated removal contract'

# If either owned resource survives bounded verification, ownership files stay.
stuck_root="$tmp_dir/stop-stuck"
mkdir -p "$stuck_root"
printf '4848\n' >"$stuck_root/gatling-workflow-batch.pid"
write_lifecycle_state "$stuck_root" RUNNING alpha alpha_mappcernabl010 0 1
make_fake_process "$stuck_root" 4848 "${owned_command[@]}"
printf '4848\n' >"$stuck_root/.live-pid"
printf 'true\n' >"$stuck_root/.container-state"
set +e
stuck_output=$(run_test_action stop "$stuck_root" "$fake_bin" "$fake_log" \
  FAKE_LIVE_PID_FILE="$stuck_root/.live-pid" FAKE_ALLOWED_KILL_FILE="$stuck_root/.live-pid" \
  FAKE_EXACT_CONTAINER=alpha_mappcernabl010 FAKE_CONTAINER_STATE_FILE="$stuck_root/.container-state" \
  FAKE_DOCKER_STOP_STICKS=1)
stuck_status=$?
set -e
((stuck_status != 0)) || fail 'stop succeeded while exact container remained running'
[[ -f "$stuck_root/gatling-workflow-batch.pid" && -f "$stuck_root/gatling-workflow-batch.state" ]] || fail 'failed verification deleted ownership files'

# An inspection error after exact stop and TERM is not proof the container is
# absent; cleanup must fail closed and preserve ownership artifacts.
verify_error_root="$tmp_dir/stop-verify-inspect-error"
mkdir -p "$verify_error_root"
printf '4949\n' >"$verify_error_root/gatling-workflow-batch.pid"
write_lifecycle_state "$verify_error_root" RUNNING alpha alpha_mappcernabl010 0 1
make_fake_process "$verify_error_root" 4949 "${owned_command[@]}"
printf '4949\n' >"$verify_error_root/.live-pid"
printf 'true\n' >"$verify_error_root/.container-state"
: >"$fake_log"
set +e
verify_error_output=$(run_test_action stop "$verify_error_root" "$fake_bin" "$fake_log" \
  FAKE_LIVE_PID_FILE="$verify_error_root/.live-pid" FAKE_ALLOWED_KILL_FILE="$verify_error_root/.live-pid" \
  FAKE_EXACT_CONTAINER=alpha_mappcernabl010 FAKE_CONTAINER_STATE_FILE="$verify_error_root/.container-state" \
  FAKE_DOCKER_VERIFY_INSPECT_ERROR=1)
verify_error_status=$?
set -e
((verify_error_status != 0)) || fail 'stop succeeded after a verification inspection error'
assert_not_contains "$verify_error_output" 'BATCH_STATE=STOPPED'
[[ -f "$verify_error_root/gatling-workflow-batch.pid" && -f "$verify_error_root/gatling-workflow-batch.state" ]] || fail 'verification inspection error deleted ownership files'

for forbidden in pkill killall 'docker ps -q' 'docker rm'; do
  assert_not_contains "$remote_text" "$forbidden"
  assert_not_contains "$controller_text" "$forbidden"
done
assert_not_contains "$remote_text" 'docker stop $(sudo docker ps'
fi

# Retain the Task 1 controller contract while allowing this Task 2 checkpoint
# to exercise all preflight behavior before the controller is implemented in
# Task 5. Task 5 removes this phase guard when its production piece is added.
if [[ ${GATLING_NODE_BATCH_FULL_CONTRACT:-0} == 1 ]]; then
  assert_contains "$controller_text" 'start'
  assert_contains "$controller_text" 'status'
  assert_contains "$controller_text" 'stop'
  assert_contains "$controller_text" 'opc@10.44.121.15'
  assert_contains "$controller_text" 'SHA256:MFpjjwtRcQ80ky/fQUoLDozygKyMNNXpBOR90tdj+Pg'
fi

printf 'GATLING_NODE_BATCH_RUNNER_TESTS=PASS\n'
