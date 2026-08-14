#!/usr/bin/env bash
set -euo pipefail

image='iad.ocir.io/idxlj5etbfyf/gatling_docker:gatling_oci_test'
network='gatling_dns_mappcernabl010'
dns_container='gatling_dns_mappcernabl010'
dns_ip='172.25.0.2'
container_suffix='mappcernabl010'
expected_hostname='INJABLFEDA001'
csv_header='workflow_name,begin_time,end_time,ok_count,ko_count'
remote_runner_path='/ablpub/OCI/Torq/Gatling/.gatling-node-batch-runner.remote.sh'

if [[ ${GATLING_NODE_BATCH_TEST_MODE:-0} == 1 ]]; then
  root=${GATLING_NODE_BATCH_ROOT:?test root is required}
  cooldown_seconds=${GATLING_NODE_BATCH_COOLDOWN:-300}
  readable_command=${GATLING_NODE_BATCH_READABLE_COMMAND:-}
  preflight_only=${GATLING_NODE_BATCH_PREFLIGHT_ONLY:-0}
  remote_runner_path=${GATLING_NODE_BATCH_REMOTE_RUNNER_PATH:?test runner path is required}
  nohup_command=${GATLING_NODE_BATCH_NOHUP_COMMAND:?test nohup command is required}
  sudo_command=${GATLING_NODE_BATCH_SUDO_COMMAND:?test sudo command is required}
  docker_command=${GATLING_NODE_BATCH_DOCKER_COMMAND:?test docker command is required}
  date_command=${GATLING_NODE_BATCH_DATE_COMMAND:?test date command is required}
  sleep_command=${GATLING_NODE_BATCH_SLEEP_COMMAND:?test sleep command is required}
  ps_command=${GATLING_NODE_BATCH_PS_COMMAND:?test ps command is required}
  kill_command=${GATLING_NODE_BATCH_KILL_COMMAND:?test kill command is required}
  start_wait_attempts=${GATLING_NODE_BATCH_START_WAIT_ATTEMPTS:-30}
  proc_root=${GATLING_NODE_BATCH_PROC_ROOT:-/proc}
  stop_wait_attempts=${GATLING_NODE_BATCH_STOP_WAIT_ATTEMPTS:-30}
else
  root=/ablpub/OCI/Torq/Gatling
  cooldown_seconds=300
  readable_command=
  preflight_only=0
  nohup_command=nohup
  sudo_command=sudo
  docker_command=docker
  date_command=date
  sleep_command=sleep
  ps_command=ps
  kill_command=kill
  start_wait_attempts=30
  proc_root=/proc
  stop_wait_attempts=30
fi

csv_path="$root/gatling-workflow-results.csv"
pid_file="$root/gatling-workflow-batch.pid"
state_file="$root/gatling-workflow-batch.state"
required_files=(config.yaml scenario.yaml scenario-data.yaml)
workflows=()
backup_path=NONE

diagnostic() {
  local workflow=$1 file=$2 key=$3 expected=$4 actual=$5
  printf 'INVALID workflow=%s file=%s key=%s expected=%s actual=%s\n' \
    "$workflow" "$file" "$key" "$expected" "$actual" >&2
}

is_readable() {
  local path=$1
  if [[ -n "$readable_command" ]]; then
    "$readable_command" "$path"
  else
    [[ -r "$path" ]]
  fi
}

trim_scalar() {
  awk '
    {
      sub(/[[:space:]]*#.*/, "")
      sub(/^[[:space:]]*/, ""); sub(/[[:space:]]*$/, "")
      if (length($0) >= 2 && ((substr($0,1,1)=="\"" && substr($0,length($0),1)=="\"") || (substr($0,1,1)==sprintf("%c",39) && substr($0,length($0),1)==sprintf("%c",39))))
        $0=substr($0,2,length($0)-2)
      print
    }
  '
}

collect_key_values() {
  local file=$1 key=$2
  awk -v wanted="$key" '
    {
      line=$0
      sub(/^[[:space:]]*/, "", line)
      sub(/^-[[:space:]]*/, "", line)
      if (line ~ ("^" wanted "[[:space:]]*:")) {
        sub(/^[^:]*:[[:space:]]*/, "", line)
        print line
      }
    }
  ' "$file" | trim_scalar
}

collect_unindented_key_values() {
  local file=$1 key=$2
  awk -v wanted="$key" '
    $0 ~ ("^" wanted "[[:space:]]*:") {
      line=$0
      sub(/^[^:]*:[[:space:]]*/, "", line)
      print line
    }
  ' "$file" | trim_scalar
}

require_all_key_values() {
  local workflow=$1 file_name=$2 key=$3 expected=$4
  local path="$root/$workflow/$file_name" value actual= count=0 failed=0
  while IFS= read -r value; do
    ((count += 1))
    actual=${value:-'<blank>'}
    if [[ "$value" != "$expected" ]]; then
      diagnostic "$workflow" "$file_name" "$key" "$expected" "$actual"
      failed=1
    fi
  done < <(collect_key_values "$path" "$key")
  if ((count == 0)); then
    diagnostic "$workflow" "$file_name" "$key" "$expected" '<missing>'
    failed=1
  fi
  ((failed == 0))
}

require_one_unindented() {
  local workflow=$1 file_name=$2 key=$3 expected=$4
  local path="$root/$workflow/$file_name" value actual count=0
  local values=()
  while IFS= read -r value; do
    values+=("$value")
    ((count += 1))
  done < <(collect_unindented_key_values "$path" "$key")
  if ((count != 1)); then
    actual="count=$count"
    ((${#values[@]} == 0)) || actual+=" values=$(IFS=,; printf '%s' "${values[*]}")"
    diagnostic "$workflow" "$file_name" "$key" "$expected" "$actual"
    return 1
  fi
  actual=${values[0]:-'<blank>'}
  if [[ ${values[0]} != "$expected" ]]; then
    diagnostic "$workflow" "$file_name" "$key" "$expected" "$actual"
    return 1
  fi
}

validate_no_placeholders() {
  local workflow=$1 file_name path match
  local failed=0
  for file_name in "${required_files[@]}"; do
    path="$root/$workflow/$file_name"
    match=$(grep -Eio 'Change_Me|REPLACE_ME' "$path" | head -n 1 || true)
    if [[ -n "$match" ]]; then
      diagnostic "$workflow" "$file_name" placeholder absent "$match"
      failed=1
    fi
  done
  ((failed == 0))
}

validate_config_authority() {
  local workflow=$1 value count=0 failed=0
  while IFS= read -r value; do
    ((count += 1))
    if [[ "$value" != ablfeda ]]; then
      diagnostic "$workflow" config.yaml authority ablfeda "${value:-<blank>}"
      failed=1
    fi
  done < <(collect_key_values "$root/$workflow/config.yaml" authority)
  if ((count != 1)); then
    diagnostic "$workflow" config.yaml authority 'exactly-one-ablfeda' "count=$count"
    failed=1
  fi
  ((failed == 0))
}

validate_scenario_data_authority() {
  local workflow=$1 file="$root/$workflow/scenario-data.yaml"
  local value name= pending=0 failed=0

  # Direct YAML authority fields are environment authority and must be ablfeda.
  while IFS= read -r value; do
    if [[ "$value" != ablfeda ]]; then
      diagnostic "$workflow" scenario-data.yaml authority ablfeda "${value:-<blank>}"
      failed=1
    fi
  done < <(collect_key_values "$file" authority)

  # Parameter pairs are prepared workflow data. Validate that an authority
  # parameter has a nonblank value, but do not confuse MillDomain with the
  # direct YAML authority field above.
  while IFS=$'\t' read -r name value; do
    [[ ${name,,} == authority ]] || continue
    pending=1
    if [[ -z "$value" ]]; then
      diagnostic "$workflow" scenario-data.yaml authority-parameter nonblank '<blank>'
      failed=1
    fi
  done < <(awk '
    function trim(s) { sub(/[[:space:]]*#.*/, "", s); sub(/^[[:space:]]*/, "", s); sub(/[[:space:]]*$/, "", s); gsub(/^\047|\047$/, "", s); gsub(/^"|"$/, "", s); return s }
    /^[[:space:]]*-[[:space:]]*name[[:space:]]*:/ {
      name=$0; sub(/^[^:]*:[[:space:]]*/, "", name); name=trim(name); waiting=1; next
    }
    waiting && /^[[:space:]]*value[[:space:]]*:/ {
      value=$0; sub(/^[^:]*:[[:space:]]*/, "", value); print name "\t" trim(value); waiting=0
    }
  ' "$file")
  : "$pending"
  ((failed == 0))
}

global_record_counts() {
  local file=$1
  awk '
    function indent(s, t) { t=s; sub(/[^ ].*$/, "", t); return length(t) }
    function scalar(s) {
      sub(/^[^:]*:[[:space:]]*/, "", s)
      sub(/[[:space:]]*#.*$/, "", s)
      sub(/^[[:space:]]*/, "", s); sub(/[[:space:]]*$/, "", s)
      gsub(/^\047|\047$/, "", s); gsub(/^"|"$/, "", s)
      return s
    }
    function finish_record() { if (in_record && identity) identities++; identity=0 }
    /^[[:space:]]*globalDataSets[[:space:]]*:/ { section=1; record_indent=-1; next }
    /^[[:space:]]*scenarioDataSets[[:space:]]*:/ { finish_record(); section=0; done=1 }
    section && /^[[:space:]]*-[[:space:]]/ {
      current_indent=indent($0)
      if (record_indent < 0 || current_indent < record_indent) record_indent=current_indent
    }
    section { lines[++n]=$0 }
    END {
      if (record_indent < 0) { print "0 0"; exit }
      for (i=1; i<=n; i++) {
        line=lines[i]
        if (line ~ /^[[:space:]]*-[[:space:]]/ && indent(line)==record_indent) {
          finish_record(); records++; in_record=1; waiting=0
        }
        if (!in_record) continue
        if (line ~ /^[[:space:]]*-[[:space:]]*name[[:space:]]*:/) {
          name=tolower(scalar(line))
          waiting=(name ~ /^(username|user_id|userid|prsnl_id|personnel_id)/)
          continue
        }
        if (waiting && line ~ /^[[:space:]]*value[[:space:]]*:/) {
          if (scalar(line) != "") identity=1
          waiting=0
        }
      }
      finish_record()
      print records+0, identities+0
    }
  ' "$file"
}

validate_global_data() {
  local workflow=$1 records identities failed=0
  read -r records identities < <(global_record_counts "$root/$workflow/scenario-data.yaml")
  if ((records < 10)); then
    diagnostic "$workflow" scenario-data.yaml globalDataSets-records '>=10' "$records"
    failed=1
  fi
  if ((identities < 10)); then
    diagnostic "$workflow" scenario-data.yaml identity-records '>=10' "$identities"
    failed=1
  fi
  ((failed == 0))
}

validate_workflow() {
  local workflow=$1 failed=0
  validate_no_placeholders "$workflow" || failed=1
  require_all_key_values "$workflow" scenario.yaml startUsers 1 || failed=1
  require_all_key_values "$workflow" scenario.yaml endUsers 10 || failed=1
  require_one_unindented "$workflow" scenario.yaml durationSeconds 600 || failed=1
  require_one_unindented "$workflow" scenario.yaml rampDurationSeconds 0 || failed=1
  validate_config_authority "$workflow" || failed=1
  validate_scenario_data_authority "$workflow" || failed=1
  validate_global_data "$workflow" || failed=1
  ((failed == 0))
}

list_workflows() {
  local dir workflow file missing failed=0
  workflows=()
  while IFS= read -r -d '' dir; do
    workflow=${dir##*/}
    if [[ ! "$workflow" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; then
      diagnostic "$workflow" directory basename '^[A-Za-z0-9][A-Za-z0-9_.-]*$' "$workflow"
      failed=1
      continue
    fi
    missing=0
    for file in "${required_files[@]}"; do
      if [[ ! -f "$dir/$file" ]]; then
        missing=1
      elif ! is_readable "$dir/$file"; then
        diagnostic "$workflow" "$file" readable true false
        failed=1
        missing=2
      fi
    done
    if ((missing == 1)); then
      printf 'SKIPPED workflow=%s file=required-yaml key=readable expected=config.yaml,scenario.yaml,scenario-data.yaml actual=missing-or-unreadable\n' "$workflow" >&2
      continue
    elif ((missing == 2)); then
      continue
    fi
    if validate_workflow "$workflow"; then
      workflows+=("$workflow")
    else
      failed=1
    fi
  done < <(find "$root" -mindepth 1 -maxdepth 1 -type d -print0 | LC_ALL=C sort -z)
  if ((${#workflows[@]} == 0)); then
    diagnostic discovery directory workflows '>=1' 0
    failed=1
  fi
  ((failed == 0))
}

preflight_runtime() {
  local user host running dns_running actual_ip pid name failed=0
  user=$(id -un 2>/dev/null || true)
  if [[ "$user" != opc ]]; then
    diagnostic runtime host user opc "${user:-<missing>}"
    return 1
  fi
  host=$(hostname -s 2>/dev/null || true)
  if [[ ${host,,} != ${expected_hostname,,} ]]; then
    diagnostic runtime host hostname "$expected_hostname" "${host:-<missing>}"
    return 1
  fi
  if ! "$sudo_command" -n true; then
    diagnostic runtime docker sudo noninteractive failed
    return 1
  fi
  if ! "$sudo_command" -n "$docker_command" info >/dev/null 2>&1; then
    diagnostic runtime docker info available failed
    return 1
  fi
  if ! "$sudo_command" -n "$docker_command" image inspect "$image" >/dev/null 2>&1; then
    diagnostic runtime docker image "$image" missing
    failed=1
  fi
  if ! "$sudo_command" -n "$docker_command" network inspect "$network" >/dev/null 2>&1; then
    diagnostic runtime docker network "$network" missing
    failed=1
  fi
  dns_running=$("$sudo_command" -n "$docker_command" inspect -f '{{.State.Running}}' "$dns_container" 2>/dev/null || true)
  if [[ "$dns_running" != true ]]; then
    diagnostic runtime docker dns-running true "${dns_running:-missing}"
    failed=1
  fi
  actual_ip=$("$sudo_command" -n "$docker_command" inspect -f "{{with index .NetworkSettings.Networks \"$network\"}}{{.IPAddress}}{{end}}" "$dns_container" 2>/dev/null || true)
  if [[ "$actual_ip" != "$dns_ip" ]]; then
    diagnostic runtime docker dns-ip "$dns_ip" "${actual_ip:-missing}"
    failed=1
  fi
  if [[ -f "$pid_file" ]]; then
    pid=$(head -n 1 "$pid_file" 2>/dev/null || true)
    if [[ "$pid" =~ ^[0-9]+$ ]] && "$ps_command" -p "$pid" >/dev/null 2>&1; then
      diagnostic runtime "${pid_file##*/}" owned-pid not-live "$pid"
      failed=1
    fi
  fi
  if ! running=$("$sudo_command" -n "$docker_command" ps --format '{{.Names}}' 2>/dev/null); then
    diagnostic runtime docker ps available failed
    failed=1
    running=
  fi
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    if [[ "$name" != "$dns_container" && "$name" == *_"$container_suffix" ]]; then
      diagnostic runtime docker running-suffix none "$name"
      failed=1
    fi
  done <<<"$running"
  if ! running=$("$sudo_command" -n "$docker_command" ps -a --format '{{.Names}}' 2>/dev/null); then
    diagnostic runtime docker ps-a available failed
    failed=1
    running=
  fi
  for name in "${workflows[@]}"; do
    if grep -Fx -- "${name}_${container_suffix}" <<<"$running" >/dev/null; then
      diagnostic "$name" docker container-name absent "${name}_${container_suffix}"
      failed=1
    fi
  done
  ((failed == 0))
}

preflight_all() {
  local workflow
  # Discovery scans every immediate child before returning, but a workflow
  # mismatch stops preflight before any Docker command is attempted.
  list_workflows || return 1
  preflight_runtime || return 1
  for workflow in "${workflows[@]}"; do
    printf '%s\n' "$workflow"
  done
}

backup_and_initialize_csv() {
  local timestamp candidate suffix=0
  backup_path=NONE
  if [[ -e "$csv_path" ]]; then
    timestamp=$("$date_command" +%Y%m%d-%H%M%S)
    candidate="$root/gatling-workflow-results.backup-$timestamp.csv"
    while [[ -e "$candidate" ]]; do
      ((suffix += 1))
      candidate="$root/gatling-workflow-results.backup-$timestamp-$suffix.csv"
    done
    mv -- "$csv_path" "$candidate"
    backup_path=$candidate
  fi
  printf '%s\n' 'workflow_name,begin_time,end_time,ok_count,ko_count' >"$csv_path"
}

parse_global_summary() {
  local file=$1 line ok=UNKNOWN ko=UNKNOWN
  while IFS= read -r line; do
    if [[ "$line" =~ ^\>[[:space:]]*Global[[:space:]]+\(OK=([0-9]+)[[:space:]]+KO=([0-9]+)[[:space:]]*\) ]]; then
      ok=${BASH_REMATCH[1]}
      ko=${BASH_REMATCH[2]}
    fi
  done <"$file"
  printf '%s,%s\n' "$ok" "$ko"
}

write_state() {
  local phase=$1 workflow=$2 container=$3 completed=$4 total=$5
  printf 'phase=%s\nworkflow=%s\ncontainer=%s\ncompleted=%s\ntotal=%s\n' \
    "$phase" "$workflow" "$container" "$completed" "$total" >"$state_file"
}

worker_owns_state() {
  local owner=
  [[ -f "$pid_file" ]] || return 1
  owner=$(head -n 1 "$pid_file" 2>/dev/null || true)
  [[ "$owner" == "$$" ]]
}

pid_is_live() {
  local pid=$1
  [[ "$pid" =~ ^[0-9]+$ ]] && "$ps_command" -p "$pid" >/dev/null 2>&1
}

published_worker_pid() {
  local pid=
  [[ -f "$pid_file" ]] || return 1
  pid=$(head -n 1 "$pid_file" 2>/dev/null || true)
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$pid"
}

publish_worker_pid() {
  local existing current attempt
  for ((attempt = 0; attempt < 10; attempt++)); do
    if [[ -e "$pid_file" ]]; then
      existing=$(head -n 1 "$pid_file" 2>/dev/null || true)
      if pid_is_live "$existing"; then
        diagnostic runtime "${pid_file##*/}" owned-pid not-live "$existing"
        return 1
      fi
      current=$(head -n 1 "$pid_file" 2>/dev/null || true)
      [[ "$current" == "$existing" ]] && rm -f -- "$pid_file"
      continue
    fi
    if (set -o noclobber; printf '%s\n' "$$" >"$pid_file") 2>/dev/null; then
      return 0
    fi
  done
  diagnostic runtime "${pid_file##*/}" owner "$$" publish-failed
  return 1
}

clear_owned_worker_state() {
  if worker_owns_state; then
    rm -f -- "$state_file" "$pid_file"
  fi
}

run_worker() {
  local workflow container begin_time end_time counts completed=0
  local total=${#workflows[@]} attempt
  local docker_args=()

  publish_worker_pid

  trap 'clear_owned_worker_state; exit 130' HUP INT TERM
  for workflow in "${workflows[@]}"; do
    container="${workflow}_${container_suffix}"
    write_state RUNNING "$workflow" "$container" "$completed" "$total"
    docker_args=(
      run --rm
      --log-opt max-size=10m
      --log-opt max-file=3
      --network gatling_dns_mappcernabl010
      --dns 172.25.0.2
      --name "$container"
      -e MAVEN_GOAL=gatling-crank:crank
      -e MAVEN_OFFLINE=true
      -e GATLING_MAX_HEAP=4g
      -v "$root/$workflow:/gatling/dataDirectory"
      -v "$root/$workflow/Report:/gatling/results"
      iad.ocir.io/idxlj5etbfyf/gatling_docker:gatling_oci_test
    )
    begin_time=$("$date_command" --iso-8601=seconds)
    if "$sudo_command" -n "$docker_command" "${docker_args[@]}" >"$root/$workflow/gatling.out" 2>&1; then
      :
    fi
    end_time=$("$date_command" --iso-8601=seconds)
    counts=$(parse_global_summary "$root/$workflow/gatling.out")
    printf '%s,%s,%s,%s\n' "$workflow" "$begin_time" "$end_time" "$counts" >>"$csv_path"
    sync -f "$csv_path"
    ((completed += 1))
    if ((completed < total)); then
      write_state COOLDOWN "$workflow" "$container" "$completed" "$total"
      "$sleep_command" "$cooldown_seconds"
    fi
  done
  clear_owned_worker_state
  trap - HUP INT TERM
}

terminate_and_verify() {
  local pid=$1 attempt
  pid_is_live "$pid" || return 0
  "$kill_command" -TERM "$pid" 2>/dev/null || true
  for ((attempt = 0; attempt < 30; attempt++)); do
    pid_is_live "$pid" || return 0
    "$sleep_command" 0.1
  done
  "$kill_command" -KILL "$pid" 2>/dev/null || true
  for ((attempt = 0; attempt < 30; attempt++)); do
    pid_is_live "$pid" || return 0
    "$sleep_command" 0.1
  done
  diagnostic runtime process terminated true "$pid"
  return 1
}

clean_worker_files_if_owned() {
  local worker_pid=$1 current=
  [[ -f "$pid_file" ]] || return 0
  current=$(head -n 1 "$pid_file" 2>/dev/null || true)
  if [[ "$current" == "$worker_pid" ]]; then
    rm -f -- "$state_file" "$pid_file"
  fi
}

fail_started_batch() {
  local reason=$1 launcher_pid=$2 worker_pid=${3:-} failed=0
  if [[ "$worker_pid" =~ ^[0-9]+$ ]]; then
    terminate_and_verify "$worker_pid" || failed=1
    clean_worker_files_if_owned "$worker_pid"
  fi
  terminate_and_verify "$launcher_pid" || failed=1
  wait "$launcher_pid" 2>/dev/null || true
  printf 'BATCH_STATE=FAILED reason=%s\n' "$reason" >&2
  ((failed == 0))
}

start_batch() {
  if [[ "$preflight_only" == 1 ]]; then
    preflight_all
    return 0
  fi
  local launcher_pid worker_pid= phase first_workflow attempt
  preflight_all >/dev/null
  backup_and_initialize_csv
  "$nohup_command" "$sudo_command" -n bash "$remote_runner_path" __worker \
    >"$root/gatling-workflow-batch.log" 2>&1 </dev/null &
  launcher_pid=$!

  for ((attempt = 0; attempt < start_wait_attempts; attempt++)); do
    worker_pid=$(published_worker_pid || true)
    if [[ -f "$state_file" ]]; then
      phase=$(sed -n 's/^phase=//p' "$state_file")
      first_workflow=$(sed -n 's/^workflow=//p' "$state_file")
      if [[ "$phase" == RUNNING && -n "$first_workflow" ]] && pid_is_live "$worker_pid"; then
        printf 'BATCH_STATE=STARTED\n'
        printf 'VALIDATED_WORKFLOWS=%s\n' "${#workflows[@]}"
        printf 'CSV_PATH=%s\n' "$csv_path"
        printf 'BACKUP_PATH=%s\n' "$backup_path"
        printf 'WORKER_PID=%s\n' "$worker_pid"
        printf 'FIRST_WORKFLOW=%s\n' "$first_workflow"
        return 0
      fi
    fi
    if ! pid_is_live "$launcher_pid"; then
      fail_started_batch worker-exited-before-state "$launcher_pid" "$worker_pid" || true
      return 1
    fi
    "$sleep_command" 1
  done
  worker_pid=$(published_worker_pid || true)
  fail_started_batch state-timeout "$launcher_pid" "$worker_pid" || true
  return 1
}

state_value() {
  local key=$1
  awk -F= -v wanted="$key" '$1 == wanted { sub(/^[^=]*=/, ""); print }' "$state_file"
}

load_valid_state() {
  local key value count
  [[ -f "$state_file" ]] || return 1
  for key in phase workflow container completed total; do
    value=$(state_value "$key")
    count=$(state_value "$key" | awk 'END { print NR+0 }')
    [[ "$count" == 1 ]] || return 1
    printf -v "state_$key" '%s' "$value"
  done
  [[ "$state_phase" == RUNNING || "$state_phase" == COOLDOWN ]] || return 1
  [[ "$state_workflow" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || return 1
  [[ "$state_container" == "${state_workflow}_${container_suffix}" ]] || return 1
  [[ "$state_completed" =~ ^[0-9]+$ && "$state_total" =~ ^[0-9]+$ ]] || return 1
  ((state_completed <= state_total))
}

read_process_command() {
  local pid=$1 path="$proc_root/$pid/cmdline"
  [[ -r "$path" ]] || return 1
  tr '\0' ' ' <"$path" | sed 's/[[:space:]]*$//'
}

worker_command_is_owned() {
  local command=$1
  [[ " $command " == *" /ablpub/OCI/Torq/Gatling/.gatling-node-batch-runner.remote.sh "* && \
     " $command " == *" __worker "* ]]
}

inspect_exact_container() {
  local container=$1 names running
  if ! names=$("$sudo_command" -n "$docker_command" ps -a \
      --filter "name=^/${container}$" --format '{{.Names}}' 2>/dev/null); then
    printf 'ERROR\n'
    return 0
  fi
  if [[ -z "$names" ]]; then
    printf 'ABSENT\n'
    return 0
  fi
  [[ "$names" == "$container" ]] || { printf 'ERROR\n'; return 0; }
  if ! running=$("$sudo_command" -n "$docker_command" inspect \
      -f '{{.State.Running}}' "$container" 2>/dev/null); then
    printf 'ERROR\n'
    return 0
  fi
  case "$running" in
    true) printf 'RUNNING\n' ;;
    false) printf 'ABSENT\n' ;;
    *) printf 'ERROR\n' ;;
  esac
}

completed_csv_rows() {
  local header lines
  [[ -f "$csv_path" ]] || { printf '0\n'; return 0; }
  IFS= read -r header <"$csv_path" || true
  [[ "$header" == "$csv_header" ]] || return 1
  lines=$(awk 'END { print NR+0 }' "$csv_path")
  [[ "$lines" =~ ^[0-9]+$ ]] || return 1
  ((lines > 0)) || return 1
  printf '%s\n' "$((lines - 1))"
}

print_latest_results() {
  local completed=$1
  [[ -f "$csv_path" ]] || return 0
  printf 'LATEST_RESULTS\n%s\n' "$csv_header"
  ((completed == 0)) || tail -n +2 "$csv_path" | tail -n 5
}

print_active_status() {
  local batch_state=$1 pid=$2 command=$3 completed=$4
  printf 'BATCH_STATE=%s\n' "$batch_state"
  printf 'WORKER_PID=%s\n' "$pid"
  printf 'PROCESS_COMMAND=%s\n' "$command"
  printf 'ACTIVE_WORKFLOW=%s\n' "$state_workflow"
  printf 'ACTIVE_CONTAINER=%s\n' "$state_container"
  printf 'COMPLETED=%s\n' "$completed"
  printf 'TOTAL=%s\n' "$state_total"
  print_latest_results "$completed"
}

status_batch() {
  local pid= command= inspection= csv_completed=0
  if [[ ! -e "$pid_file" ]]; then
    if [[ -e "$state_file" ]]; then
      printf 'BATCH_STATE=STALE_STATE\n'
      return 0
    fi
    if [[ ! -e "$csv_path" ]]; then
      printf 'BATCH_STATE=NOT_STARTED\n'
      return 0
    fi
    csv_completed=$(completed_csv_rows) || { printf 'BATCH_STATE=STALE_STATE\n'; return 0; }
    if ((csv_completed > 0)); then
      printf 'BATCH_STATE=COMPLETED\nCOMPLETED=%s\nTOTAL=%s\n' "$csv_completed" "$csv_completed"
      print_latest_results "$csv_completed"
    else
      printf 'BATCH_STATE=STALE_STATE\n'
    fi
    return 0
  fi

  pid=$(head -n 1 "$pid_file" 2>/dev/null || true)
  if [[ ! "$pid" =~ ^[0-9]+$ ]] || ! pid_is_live "$pid"; then
    printf 'BATCH_STATE=STALE_STATE\n'
    return 0
  fi
  command=$(read_process_command "$pid" || true)
  if ! worker_command_is_owned "$command" || ! load_valid_state; then
    printf 'BATCH_STATE=STALE_STATE\n'
    return 0
  fi
  csv_completed=$(completed_csv_rows) || { printf 'BATCH_STATE=STALE_STATE\n'; return 0; }
  if [[ "$csv_completed" != "$state_completed" ]]; then
    printf 'BATCH_STATE=STALE_STATE\n'
    return 0
  fi
  inspection=$(inspect_exact_container "$state_container")
  case "$state_phase|$inspection" in
    'RUNNING|RUNNING') print_active_status RUNNING "$pid" "$command" "$csv_completed" ;;
    'COOLDOWN|ABSENT') print_active_status COOLDOWN "$pid" "$command" "$csv_completed" ;;
    *) printf 'BATCH_STATE=STALE_STATE\n' ;;
  esac
}

stop_refused() {
  printf 'BATCH_STATE=STOP_REFUSED reason=%s\n' "$1" >&2
  return 1
}

stop_batch() {
  local pid command expected_container inspection process_live container_live attempt current
  [[ -f "$pid_file" ]] || { stop_refused missing-pid; return 1; }
  pid=$(head -n 1 "$pid_file" 2>/dev/null || true)
  [[ "$pid" =~ ^[0-9]+$ ]] || { stop_refused invalid-pid; return 1; }
  pid_is_live "$pid" || { stop_refused dead-pid; return 1; }
  command=$(read_process_command "$pid" || true)
  worker_command_is_owned "$command" || { stop_refused unowned-process; return 1; }
  load_valid_state || { stop_refused invalid-state; return 1; }
  expected_container="${state_workflow}_${container_suffix}"
  [[ "$state_container" == "$expected_container" ]] || { stop_refused invalid-container; return 1; }
  [[ "$expected_container" != "$dns_container" ]] || { stop_refused dns-container; return 1; }

  inspection=$(inspect_exact_container "$expected_container")
  case "$inspection" in
    RUNNING) container_live=1 ;;
    ABSENT) container_live=0 ;;
    ERROR) stop_refused container-inspection-error; return 1 ;;
  esac

  if ((container_live)); then
    "$sudo_command" -n "$docker_command" stop "$expected_container"
  fi
  "$sudo_command" -n "$kill_command" -TERM "$pid"

  process_live=1
  container_live=1
  for ((attempt = 0; attempt < stop_wait_attempts; attempt++)); do
    pid_is_live "$pid" && process_live=1 || process_live=0
    inspection=$(inspect_exact_container "$expected_container")
    case "$inspection" in
      RUNNING) container_live=1 ;;
      ABSENT) container_live=0 ;;
      ERROR)
        printf 'BATCH_STATE=STOP_FAILED reason=container-inspection-error\n' >&2
        return 1
        ;;
    esac
    ((process_live == 0 && container_live == 0)) && break
    ((attempt + 1 == stop_wait_attempts)) || "$sleep_command" 0.1
  done
  if ((process_live || container_live)); then
    printf 'BATCH_STATE=STOP_FAILED reason=verification-timeout\n' >&2
    return 1
  fi
  current=$(head -n 1 "$pid_file" 2>/dev/null || true)
  [[ "$current" == "$pid" ]] || { stop_refused ownership-changed; return 1; }
  if ! "$sudo_command" -n rm -f -- "$pid_file" "$state_file"; then
    printf 'BATCH_STATE=STOP_FAILED reason=cleanup-failed\n' >&2
    return 1
  fi
  printf 'BATCH_STATE=STOPPED\n'
}

action=${1:-}
case "$action" in
  start) start_batch ;;
  status) status_batch ;;
  stop) stop_batch ;;
  __worker) list_workflows >/dev/null; run_worker ;;
  __test_initialize)
    [[ ${GATLING_NODE_BATCH_TEST_MODE:-0} == 1 ]] || exit 2
    preflight_all >/dev/null
    backup_and_initialize_csv
    printf 'CSV_PATH=%s\nBACKUP_PATH=%s\n' "$csv_path" "$backup_path"
    ;;
  __test_worker)
    [[ ${GATLING_NODE_BATCH_TEST_MODE:-0} == 1 ]] || exit 2
    list_workflows >/dev/null
    run_worker
    ;;
  *) printf 'usage: %s {start|status|stop}\n' "${0##*/}" >&2; exit 2 ;;
esac
