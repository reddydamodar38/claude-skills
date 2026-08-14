#!/usr/bin/env bash
set -u

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <preview-log> [expected-not-queued-csv]" >&2
  exit 64
fi

preview_log=$1
expected_csv=${2:-DM_INFO,DM_STAT_TABLE,DM_PROCESS_EVENT,DM_PROCESS}

if [[ ! -r "$preview_log" ]]; then
  echo "Unable to read preview log: $preview_log" >&2
  exit 66
fi

awk -v expected_csv="$expected_csv" '
BEGIN {
  expected_count = split(toupper(expected_csv), expected_items, ",")
  for (i = 1; i <= expected_count; i++) {
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", expected_items[i])
    if (expected_items[i] != "") {
      expected[expected_items[i]] = 1
    }
  }
}

/^[[:space:]]*[TI][[:space:]]/ {
  row = $0
  gsub(/[[:space:]]+/, " ", row)
  gsub(/^ | $/, "", row)
  field_count = split(row, fields, " ")

  object_name = toupper(fields[3])
  stale_flag = toupper(fields[5])
  if (field_count >= 6 && (stale_flag == "YES" || stale_flag == "NO")) {
    status = toupper(fields[6])
    if (status == "NOT" && field_count >= 7 && toupper(fields[7]) == "QUEUED") {
      status = "NOT QUEUED"
    }
  } else {
    status = toupper(fields[4])
    if (status == "NOT" && field_count >= 5 && toupper(fields[5]) == "QUEUED") {
      status = "NOT QUEUED"
    }
  }

  object_rows++
  status_count[status]++

  if (status == "FAILURE") {
    failure_rows++
    exception[++exception_count] = "FAILURE " row
  } else if (status == "NOT QUEUED") {
    if (!(object_name in expected)) {
      unexpected_rows++
      exception[++exception_count] = "UNEXPECTED_NOT_QUEUED " row
    } else {
      exception[++exception_count] = "EXPECTED_NOT_QUEUED " row
    }
  }
}

END {
  print "OBJECT_ROWS " (object_rows + 0)

  status_total = 0
  for (status in status_count) {
    status_names[++status_total] = status
  }
  for (i = 2; i <= status_total; i++) {
    value = status_names[i]
    j = i - 1
    while (j >= 1 && status_names[j] > value) {
      status_names[j + 1] = status_names[j]
      j--
    }
    status_names[j + 1] = value
  }
  for (i = 1; i <= status_total; i++) {
    status = status_names[i]
    print "STATUS " status " " status_count[status]
  }
  for (i = 1; i <= exception_count; i++) {
    print "EXCEPTION " exception[i]
  }

  if (failure_rows > 0) {
    exit 2
  }
  if (unexpected_rows > 0) {
    exit 3
  }
  exit 0
}
' "$preview_log"
