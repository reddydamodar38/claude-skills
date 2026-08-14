#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  run_gatling_docker_test.sh --test-folder REMOTE_PATH (--prepare-only | --execute) [options]

Options:
  --allow-shared-data       Approve reuse when globalDataSets has fewer than 10 entries.
  --key-path PATH           SSH private key (default: ~/.ssh/id_ed25519_injablfeda001).
  --known-hosts-path PATH   Pinned known_hosts file (default: ~/.ssh/known_hosts).
  --local-csv PATH          Local execution register.
  --dns-container NAME      Docker DNS container override.
  --docker-network NAME     Docker network override.
  --docker-image IMAGE      Approved image override.
  --expected-hostname NAME  Expected short hostname override.
  --help                    Show this help.
USAGE
}

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
skill_dir=$(cd "$script_dir/.." && pwd)
validator="$script_dir/validate_test_folder.rb"

test_folder=""
mode=""
allow_shared_data=false
key_path="$HOME/.ssh/id_ed25519_injablfeda001"
known_hosts_path="$HOME/.ssh/known_hosts"
local_csv="/Users/ayushsaxena/Documents/gatling-test-execution-register.csv"
expected_hostname="INJABLFEDA001"
target_host="10.44.121.15"
target_user="opc"
test_root="/ablpub/OCI/Torq/Gatling"
dns_container="gatling_dns_mappcernabl010"
docker_network="gatling_dns_mappcernabl010"
expected_dns_ip="172.25.0.2"
container_suffix="mappcernabl010"
docker_image="iad.ocir.io/idxlj5etbfyf/gatling_docker:gatling_oci_test"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --test-folder)
      test_folder=${2:-}
      shift 2
      ;;
    --prepare-only)
      mode="prepare"
      shift
      ;;
    --execute)
      mode="execute"
      shift
      ;;
    --allow-shared-data)
      allow_shared_data=true
      shift
      ;;
    --key-path)
      key_path=${2:-}
      shift 2
      ;;
    --known-hosts-path)
      known_hosts_path=${2:-}
      shift 2
      ;;
    --local-csv)
      local_csv=${2:-}
      shift 2
      ;;
    --dns-container)
      dns_container=${2:-}
      shift 2
      ;;
    --docker-network)
      docker_network=${2:-}
      shift 2
      ;;
    --docker-image)
      docker_image=${2:-}
      shift 2
      ;;
    --expected-hostname)
      expected_hostname=${2:-}
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

if [ -z "$test_folder" ] || [ "${test_folder#/}" = "$test_folder" ]; then
  echo "--test-folder must be an absolute remote path." >&2
  exit 64
fi
case "$test_folder" in
  "$test_root"/*) ;;
  *)
    echo "--test-folder must be beneath $test_root." >&2
    exit 64
    ;;
esac
if [ "$mode" != "prepare" ] && [ "$mode" != "execute" ]; then
  echo "Choose exactly one mode: --prepare-only or --execute." >&2
  exit 64
fi
if [ ! -r "$key_path" ]; then
  echo "SSH key is missing or unreadable: $key_path" >&2
  exit 66
fi
if [ ! -r "$known_hosts_path" ]; then
  echo "Pinned known_hosts file is missing or unreadable: $known_hosts_path" >&2
  exit 66
fi
if [ ! -x "$validator" ]; then
  echo "Validator is missing or not executable: $validator" >&2
  exit 66
fi

local_temp=$(mktemp -d "${TMPDIR:-/tmp}/gatling-docker-test-runner.XXXXXX")
chmod 700 "$local_temp"
cleanup_local_temp() {
  rm -rf "$local_temp"
}
trap cleanup_local_temp EXIT

ssh_options=(
  -o BatchMode=yes
  -o ConnectTimeout=15
  -o StrictHostKeyChecking=yes
  -o "UserKnownHostsFile=$known_hosts_path"
  -o "GlobalKnownHostsFile=$known_hosts_path"
  -o UpdateHostKeys=no
  -o IdentitiesOnly=yes
  -o PreferredAuthentications=publickey
  -o PasswordAuthentication=no
  -o KbdInteractiveAuthentication=no
  -o GSSAPIAuthentication=no
  -i "$key_path"
)
target="$target_user@$target_host"

identity_output=$(ssh "${ssh_options[@]}" "$target" 'printf "USER=%s\nHOST=%s\n" "$(id -un)" "$(hostname -s)"')
actual_user=$(printf '%s\n' "$identity_output" | sed -n 's/^USER=//p' | tail -1)
actual_hostname=$(printf '%s\n' "$identity_output" | sed -n 's/^HOST=//p' | tail -1)

if [ "$actual_user" != "$target_user" ]; then
  echo "Connected user mismatch: expected=$target_user actual=$actual_user" >&2
  exit 69
fi
if [ "$(printf '%s' "$actual_hostname" | tr '[:lower:]' '[:upper:]')" != "$(printf '%s' "$expected_hostname" | tr '[:lower:]' '[:upper:]')" ]; then
  echo "Connected hostname mismatch: expected=$expected_hostname actual=$actual_hostname" >&2
  exit 69
fi

fetch_remote_file() {
  remote_name=$1
  local_name=$2
  remote_path="$test_folder/$remote_name"
  remote_quoted=$(printf '%q' "$remote_path")
  ssh "${ssh_options[@]}" "$target" "cat -- $remote_quoted" > "$local_temp/$local_name"
  chmod 600 "$local_temp/$local_name"
}

fetch_remote_file "config.yaml" "config.yaml"
fetch_remote_file "scenario.yaml" "scenario.yaml"
fetch_remote_file "scenario-data.yaml" "scenario-data.yaml"

validator_args=(--folder "$local_temp" --required-users 10)
if $allow_shared_data; then
  validator_args+=(--allow-shared-data)
fi
ruby "$validator" "${validator_args[@]}"

prepare_output=$(ssh "${ssh_options[@]}" "$target" bash -s -- \
  "$test_folder" "$dns_container" "$docker_network" "$docker_image" "$expected_dns_ip" <<'REMOTE_PREPARE'
set -euo pipefail

test_folder=$1
dns_container=$2
docker_network=$3
docker_image=$4
expected_dns_ip=$5
docker_cmd=(sudo -n docker)

for name in config.yaml scenario.yaml scenario-data.yaml; do
  test -r "$test_folder/$name" || {
    echo "Remote file is missing or unreadable: $test_folder/$name" >&2
    exit 1
  }
done

"${docker_cmd[@]}" info >/dev/null
"${docker_cmd[@]}" image inspect "$docker_image" >/dev/null
"${docker_cmd[@]}" inspect "$dns_container" >/dev/null
"${docker_cmd[@]}" network inspect "$docker_network" >/dev/null

dns_running=$("${docker_cmd[@]}" inspect --format '{{.State.Running}}' "$dns_container")
dns_ip=$("${docker_cmd[@]}" inspect \
  --format "{{with index .NetworkSettings.Networks \"$docker_network\"}}{{.IPAddress}}{{end}}" \
  "$dns_container")
if [ "$dns_ip" != "$expected_dns_ip" ]; then
  echo "DNS address mismatch: expected=$expected_dns_ip actual=${dns_ip:-not-assigned}" >&2
  exit 1
fi

echo "REMOTE_DOCKER_GATE=PASS dns_running=$dns_running dns_ip=${dns_ip:-not-assigned}"
REMOTE_PREPARE
)
printf '%s\n' "$prepare_output"

if [ "$mode" = "prepare" ]; then
  echo "PREPARE_ONLY_OK host=$expected_hostname test_folder=$test_folder source_files_modified=false"
  exit 0
fi

remote_output_path="$local_temp/remote-execution.out"
set +e
ssh "${ssh_options[@]}" "$target" bash -s -- \
  "$test_folder" "$expected_hostname" "$target_host" "$dns_container" "$docker_network" "$docker_image" \
  "$container_suffix" "$expected_dns_ip" \
  <<'REMOTE_EXECUTE' | tee "$remote_output_path"
set -u -o pipefail

test_folder=$1
expected_hostname=$2
node_ip=$3
dns_container=$4
docker_network=$5
docker_image=$6
container_suffix=$7
expected_dns_ip=$8
docker_cmd=(sudo -n docker)

test_name=$(basename "$test_folder")
run_id=$(date '+%Y%m%d-%H%M%S')
safe_test_name=$(printf '%s' "$test_name" | tr -c 'A-Za-z0-9_.-' '-')
run_container="${safe_test_name}_${container_suffix}"
report_path="$test_folder/Report"
log_path="$test_folder/${safe_test_name}-${run_id}.out"

if [ "$("${docker_cmd[@]}" inspect --format '{{.State.Running}}' "$dns_container")" != "true" ]; then
  "${docker_cmd[@]}" start "$dns_container" >/dev/null || exit 1
fi

dns_ip=$("${docker_cmd[@]}" inspect \
  --format "{{with index .NetworkSettings.Networks \"$docker_network\"}}{{.IPAddress}}{{end}}" \
  "$dns_container")
if [ "$dns_ip" != "$expected_dns_ip" ]; then
  echo "DNS address mismatch: expected=$expected_dns_ip actual=${dns_ip:-not-assigned}" >&2
  exit 1
fi

if "${docker_cmd[@]}" ps -a --format '{{.Names}}' | grep -Fx "$run_container" >/dev/null; then
  echo "Execution container already exists: $run_container" >&2
  exit 1
fi

mkdir -p "$report_path"
report_marker="$report_path/.gatling-run-marker-$run_id"
touch "$report_marker" || exit 1
cleanup_report_marker() {
  rm -f "$report_marker"
}
trap cleanup_report_marker EXIT

node_timezone=$(date '+%z %Z')
command_start_time=$(date '+%Y-%m-%dT%H:%M:%S%z')
command_start_epoch=$(date '+%s')

echo "GTR_START test_name=$test_name node=$expected_hostname node_time=$command_start_time"
echo "GTR_PATHS log=$log_path report=$report_path"
echo "GTR_DOCKER container=$run_container network=$docker_network dns=$dns_ip"

"${docker_cmd[@]}" run \
  --rm \
  --log-opt max-size=10m \
  --log-opt max-file=3 \
  --network "$docker_network" \
  --dns "$dns_ip" \
  --name "$run_container" \
  -e MAVEN_GOAL='gatling-crank:crank' \
  -e MAVEN_OFFLINE='true' \
  -e GATLING_MAX_HEAP='4g' \
  -v "$test_folder:/gatling/dataDirectory" \
  -v "$report_path:/gatling/results" \
  "$docker_image" \
  > "$log_path" 2>&1 &

docker_client_pid=$!
while kill -0 "$docker_client_pid" 2>/dev/null; do
  sleep 30
  if kill -0 "$docker_client_pid" 2>/dev/null; then
    echo "GTR_PROGRESS node_time=$(date '+%Y-%m-%dT%H:%M:%S%z') container=$run_container"
  fi
done

wait "$docker_client_pid"
test_exit_code=$?
command_end_time=$(date '+%Y-%m-%dT%H:%M:%S%z')
command_end_epoch=$(date '+%s')

completion_marker=false
if grep -qE 'Simulation .* completed in [0-9]+ seconds' "$log_path"; then
  completion_marker=true
fi

actual_duration_seconds=$(grep -E 'Simulation .* completed in [0-9]+ seconds' "$log_path" \
  | tail -1 \
  | sed -E 's/.* completed in ([0-9]+) seconds.*/\1/' 2>/dev/null)
if ! printf '%s' "$actual_duration_seconds" | grep -Eq '^[0-9]+$'; then
  actual_duration_seconds=$((command_end_epoch - command_start_epoch))
fi

printed_end_time=$(grep -Eo '[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} [A-Za-z]{2,5}' "$log_path" \
  | tail -1 2>/dev/null)
workload_end_time=""
if [ -n "$printed_end_time" ]; then
  workload_end_time=$(date -d "$printed_end_time" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)
fi
if [ -z "$workload_end_time" ]; then
  workload_end_time=$command_end_time
fi

workload_start_time=$(date -d "$workload_end_time - $actual_duration_seconds seconds" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)
if [ -z "$workload_start_time" ]; then
  workload_start_time=$command_start_time
fi

ko_count=$(grep '^> Global' "$log_path" \
  | tail -1 \
  | sed -E 's/.*KO= *([0-9]+).*/\1/' 2>/dev/null)
if ! printf '%s' "$ko_count" | grep -Eq '^[0-9]+$'; then
  ko_count="unknown"
fi

report_file=$(find "$report_path" -type f -newer "$report_marker" -print -quit 2>/dev/null)
report_created=false
if [ -n "$report_file" ]; then
  report_created=true
fi

if [ "$test_exit_code" -eq 0 ] && $completion_marker && $report_created && [ "$ko_count" = "0" ]; then
  final_status="PASS"
elif $completion_marker && $report_created; then
  final_status="COMPLETED_WITH_FAILURES"
else
  final_status="EXECUTION_FAILED"
fi

echo "GTR_RESULT_TEST_NAME=$test_name"
echo "GTR_RESULT_TEST_FOLDER=$test_folder"
echo "GTR_RESULT_TEST_NODE=$expected_hostname"
echo "GTR_RESULT_TEST_HOST=$node_ip"
echo "GTR_RESULT_NODE_TIMEZONE=$node_timezone"
echo "GTR_RESULT_COMMAND_START=$command_start_time"
echo "GTR_RESULT_COMMAND_END=$command_end_time"
echo "GTR_RESULT_WORKLOAD_START=$workload_start_time"
echo "GTR_RESULT_WORKLOAD_END=$workload_end_time"
echo "GTR_RESULT_DURATION_SECONDS=$actual_duration_seconds"
echo "GTR_RESULT_EXIT_CODE=$test_exit_code"
echo "GTR_RESULT_STATUS=$final_status"
echo "GTR_RESULT_KO_COUNT=$ko_count"
echo "GTR_RESULT_LOG_PATH=$log_path"
echo "GTR_RESULT_REPORT_PATH=$report_path"
REMOTE_EXECUTE
ssh_status=${PIPESTATUS[0]}
set -e

if [ "$ssh_status" -ne 0 ]; then
  echo "Remote execution wrapper failed with SSH status $ssh_status" >&2
  exit "$ssh_status"
fi

result_value() {
  result_key=$1
  sed -n "s/^GTR_RESULT_${result_key}=//p" "$remote_output_path" | tail -1
}

result_test_name=$(result_value TEST_NAME)
result_test_folder=$(result_value TEST_FOLDER)
result_test_node=$(result_value TEST_NODE)
result_test_host=$(result_value TEST_HOST)
result_node_timezone=$(result_value NODE_TIMEZONE)
result_command_start=$(result_value COMMAND_START)
result_command_end=$(result_value COMMAND_END)
result_workload_start=$(result_value WORKLOAD_START)
result_workload_end=$(result_value WORKLOAD_END)
result_duration=$(result_value DURATION_SECONDS)
result_exit_code=$(result_value EXIT_CODE)
result_status=$(result_value STATUS)
result_ko_count=$(result_value KO_COUNT)
result_log_path=$(result_value LOG_PATH)
result_report_path=$(result_value REPORT_PATH)

for required_value in \
  "$result_test_name" "$result_test_folder" "$result_test_node" "$result_test_host" \
  "$result_node_timezone" "$result_command_start" "$result_command_end" \
  "$result_workload_start" "$result_workload_end" "$result_duration" \
  "$result_exit_code" "$result_status" "$result_log_path" "$result_report_path"
do
  if [ -z "$required_value" ]; then
    echo "Remote execution record is incomplete; local CSV was not changed." >&2
    exit 70
  fi
done

csv_quote() {
  csv_value=$1
  csv_value=${csv_value//\"/\"\"}
  printf '"%s"' "$csv_value"
}

local_csv_parent=$(dirname "$local_csv")
mkdir -p "$local_csv_parent"
if [ ! -f "$local_csv" ]; then
  printf '%s\n' 'test_name,test_folder,test_node,test_host,ssh_user,node_timezone,command_start_time,command_end_time,workload_start_time,workload_end_time,test_duration_seconds,start_users,end_users,ramp_duration_seconds,exit_code,final_status,ko_count,log_path,report_path' > "$local_csv"
fi

{
  csv_quote "$result_test_name"; printf ','
  csv_quote "$result_test_folder"; printf ','
  csv_quote "$result_test_node"; printf ','
  csv_quote "$result_test_host"; printf ','
  csv_quote "$target_user"; printf ','
  csv_quote "$result_node_timezone"; printf ','
  csv_quote "$result_command_start"; printf ','
  csv_quote "$result_command_end"; printf ','
  csv_quote "$result_workload_start"; printf ','
  csv_quote "$result_workload_end"; printf ','
  csv_quote "$result_duration"; printf ','
  csv_quote "1"; printf ','
  csv_quote "10"; printf ','
  csv_quote "600"; printf ','
  csv_quote "$result_exit_code"; printf ','
  csv_quote "$result_status"; printf ','
  csv_quote "$result_ko_count"; printf ','
  csv_quote "$result_log_path"; printf ','
  csv_quote "$result_report_path"; printf '\n'
} >> "$local_csv"
chmod 600 "$local_csv"

echo "LOCAL_CSV_UPDATED=$local_csv"
echo "FINAL_STATUS=$result_status"
echo "WORKLOAD_START=$result_workload_start"
echo "WORKLOAD_END=$result_workload_end"
echo "DURATION_SECONDS=$result_duration"
echo "REMOTE_LOG=$result_log_path"
echo "REMOTE_REPORT=$result_report_path"

if [ "$result_status" != "PASS" ]; then
  exit 2
fi
