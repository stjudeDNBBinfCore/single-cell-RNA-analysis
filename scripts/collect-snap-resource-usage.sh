#!/usr/bin/env bash
# Collect per-module LSF resource usage for a Sprocket snap downstream run.
#
# Compares requested resources (from task inputs.json) with actual usage
# reported by LSF (peak memory, CPU time, wall time, efficiency).
#
# Writes reports under out/resource_usage/ by default.
#
# Usage:
#   collect-snap-resource-usage.sh --snap-root PATH [--run-id ID | --latest] [--output PATH] [--json]

set -euo pipefail

SNAP_ROOT=""
RUN_ID=""
USE_LATEST=0
OUTPUT=""
WRITE_JSON=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --snap-root) SNAP_ROOT="$2"; shift 2 ;;
    --run-id) RUN_ID="$2"; shift 2 ;;
    --latest) USE_LATEST=1; shift ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --json) WRITE_JSON=1; shift ;;
    -h|--help)
      sed -n '2,8p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

[[ -n "${SNAP_ROOT}" ]] || {
  echo "Usage: collect-snap-resource-usage.sh --snap-root PATH [--run-id ID | --latest] [--output PATH] [--json]" >&2
  exit 1
}

SNAP_ROOT="$(cd "${SNAP_ROOT}" && pwd)"
RUNS_ROOT="${SNAP_ROOT}/out/runs/sc_rna_seq_snap_downstream"
RESOURCE_USAGE_DIR="${SNAP_ROOT}/out/resource_usage"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required but not found in PATH" >&2
  exit 1
fi

normalize_module() {
  local alias="$1"
  case "${alias}" in
    upstream) echo "upstream" ;;
    integrative*) echo "integrative" ;;
    cluster*) echo "cluster" ;;
    contamination*) echo "contamination_removal" ;;
    cell_types*) echo "cell_types" ;;
    clone_phylogeny*) echo "clone_phylogeny" ;;
    de_go*) echo "de_go" ;;
    rshiny*) echo "rshiny" ;;
    *) echo "${alias}" ;;
  esac
}

resolve_latest_run_dir() {
  local latest_link="${RUNS_ROOT}/_latest"
  if [[ -L "${latest_link}" || -d "${latest_link}" ]]; then
    local target
    target="$(readlink -f "${latest_link}" 2>/dev/null || echo "${latest_link}")"
    if [[ -d "${target}/calls" ]]; then
      echo "${target}"
      return 0
    fi
  fi
  local newest
  newest="$(find "${RUNS_ROOT}" -mindepth 1 -maxdepth 1 -type d ! -name '_latest' -printf '%T@ %p\n' 2>/dev/null \
    | sort -nr | head -1 | awk '{print $2}')"
  if [[ -n "${newest}" && -d "${newest}/calls" ]]; then
    echo "${newest}"
    return 0
  fi
  return 1
}

mem_to_gb() {
  local value="$1"
  local unit="$2"
  case "${unit}" in
    Gbytes|G) awk -v v="${value}" 'BEGIN { printf "%.4f", v }' ;;
    Mbytes|M) awk -v v="${value}" 'BEGIN { printf "%.4f", v / 1024 }' ;;
    Kbytes|K) awk -v v="${value}" 'BEGIN { printf "%.4f", v / 1024 / 1024 }' ;;
    *) echo "" ;;
  esac
}

parse_duration_seconds() {
  local raw="$1"
  sed -E 's/^([0-9.]+).*/\1/' <<<"${raw}"
}

parse_lsf_stats() {
  local job_id="$1"

  if ! command -v bjobs >/dev/null 2>&1; then
    echo "ERROR:bjobs not found" >&2
    return 1
  fi

  local lsf_status cpu_time_raw wall_time_raw exit_code max_mem_raw
  lsf_status="$(bjobs -a -noheader -o stat "${job_id}" 2>/dev/null | head -1 | tr -d '[:space:]')"
  cpu_time_raw="$(bjobs -a -noheader -o cpu_used "${job_id}" 2>/dev/null | head -1)"
  wall_time_raw="$(bjobs -a -noheader -o run_time "${job_id}" 2>/dev/null | head -1)"
  exit_code="$(bjobs -a -noheader -o exit_code "${job_id}" 2>/dev/null | head -1 | tr -d '[:space:]')"
  max_mem_raw="$(bjobs -a -noheader -o max_mem "${job_id}" 2>/dev/null | head -1)"

  if [[ -z "${lsf_status}" ]]; then
    echo "ERROR:LSF job ${job_id} not found (bjobs -a)" >&2
    return 1
  fi

  local cpu_time_sec wall_time_sec max_mem_gb avg_mem_gb=""
  local lsf_mem_efficiency_pct="" cpu_avg_efficiency_pct="" cpu_peak_efficiency_pct=""

  cpu_time_sec="$(parse_duration_seconds "${cpu_time_raw}")"
  wall_time_sec="$(parse_duration_seconds "${wall_time_raw}")"

  if [[ -n "${max_mem_raw}" && "${max_mem_raw}" != "-" ]]; then
    local max_val max_unit
    read -r max_val max_unit <<<"${max_mem_raw}"
    max_mem_gb="$(mem_to_gb "${max_val}" "${max_unit}")"
  fi

  local log
  log="$(bjobs -a -l "${job_id}" 2>/dev/null || true)"
  if [[ -n "${log}" ]]; then
    local line
    line="$(printf '%s\n' "${log}" | sed -n 's/.*AVG MEM: \([0-9.]*\) \([A-Za-z]*\).*/\1 \2/p' | head -1)"
    if [[ -n "${line}" ]]; then
      local avg_val avg_unit
      read -r avg_val avg_unit <<<"${line}"
      avg_mem_gb="$(mem_to_gb "${avg_val}" "${avg_unit}")"
    fi

    line="$(printf '%s\n' "${log}" | sed -n 's/.*MEM Efficiency: \([0-9.]*\)%.*/\1/p' | head -1)"
    [[ -n "${line}" ]] && lsf_mem_efficiency_pct="${line}"

    line="$(printf '%s\n' "${log}" | sed -n 's/.*CPU AVERAGE EFFICIENCY: \([0-9.]*\)%.*/\1/p' | head -1)"
    [[ -n "${line}" ]] && cpu_avg_efficiency_pct="${line}"

    line="$(printf '%s\n' "${log}" | sed -n 's/.*CPU PEAK EFFICIENCY: \([0-9.]*\)%.*/\1/p' | head -1)"
    [[ -n "${line}" ]] && cpu_peak_efficiency_pct="${line}"
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${lsf_status}" \
    "${cpu_time_sec}" \
    "${wall_time_sec}" \
    "${exit_code}" \
    "${max_mem_gb}" \
    "${avg_mem_gb}" \
    "${lsf_mem_efficiency_pct}" \
    "${cpu_avg_efficiency_pct}" \
    "${cpu_peak_efficiency_pct}"
}

calc_utilization_pct() {
  local actual="$1"
  local requested="$2"
  awk -v a="${actual}" -v r="${requested}" 'BEGIN {
    if (r == "" || a == "" || r + 0 <= 0) { print ""; exit }
    printf "%.2f", (a / r) * 100
  }'
}

json_number_or_null() {
  local value="$1"
  if [[ -z "${value}" ]]; then
    echo "null"
  else
    echo "${value}"
  fi
}

resolve_run_dir() {
  if [[ -n "${RUN_ID}" ]]; then
    local run_dir="${RUNS_ROOT}/${RUN_ID}"
    if [[ -d "${run_dir}/calls" ]]; then
      echo "${run_dir}"
      return 0
    fi
    echo "Run directory not found: ${run_dir}" >&2
    return 1
  fi

  if [[ "${USE_LATEST}" -eq 1 ]] || [[ -z "${RUN_ID}" ]]; then
    resolve_latest_run_dir
    return $?
  fi

  return 1
}

RUN_DIR="$(resolve_run_dir)" || {
  echo "No Sprocket run directory found under ${RUNS_ROOT}" >&2
  exit 1
}

RUN_ID="$(basename "${RUN_DIR}")"
CALLS_DIR="${RUN_DIR}/calls"

[[ -d "${CALLS_DIR}" ]] || {
  echo "Missing calls directory: ${CALLS_DIR}" >&2
  exit 1
}

if [[ -z "${OUTPUT}" ]]; then
  OUTPUT="${RESOURCE_USAGE_DIR}/resource_usage_${RUN_ID}.csv"
fi

mkdir -p "$(dirname "${OUTPUT}")"
JSON_OUTPUT="${OUTPUT%.csv}.json"

tmp_rows="$(mktemp)"
trap 'rm -f "${tmp_rows}"' EXIT

header="run_id,module,call_alias,lsf_job_id,lsf_status,requested_cpu,requested_memory_gb,requested_lsf_queue,actual_max_memory_gb,actual_avg_memory_gb,memory_utilization_pct,lsf_mem_efficiency_pct,cpu_time_sec,wall_time_sec,cpu_avg_efficiency_pct,cpu_peak_efficiency_pct,lsf_exit_code"
echo "${header}" > "${OUTPUT}"

module_count=0
queried_count=0

for call_path in "${CALLS_DIR}"/*/; do
  [[ -d "${call_path}" ]] || continue
  call_alias="$(basename "${call_path}")"
  module="$(normalize_module "${call_alias}")"
  attempt_dir="${call_path}attempts/0"
  job_id_file="${attempt_dir}/job_id"
  inputs_file="${call_path}inputs.json"

  [[ -f "${job_id_file}" ]] || continue
  module_count=$((module_count + 1))

  job_id="$(tr -d '[:space:]' < "${job_id_file}")"
  requested_cpu=""
  requested_memory_gb=""
  requested_lsf_queue=""

  if [[ -f "${inputs_file}" ]]; then
    requested_cpu="$(jq -r '.cpu // empty' "${inputs_file}")"
    requested_memory_gb="$(jq -r '.memory_gb // empty' "${inputs_file}")"
    requested_lsf_queue="$(jq -r '.lsf_queue // empty' "${inputs_file}")"
  fi

  stats="$(parse_lsf_stats "${job_id}" 2>/dev/null || true)"
  if [[ -z "${stats}" ]]; then
    echo "${RUN_ID},${module},${call_alias},${job_id},NOT_FOUND,${requested_cpu},${requested_memory_gb},${requested_lsf_queue},,,,,,,," >> "${OUTPUT}"
    continue
  fi

  queried_count=$((queried_count + 1))
  IFS=$'\t' read -r lsf_status cpu_time_sec wall_time_sec exit_code max_mem_gb avg_mem_gb \
    lsf_mem_efficiency_pct cpu_avg_efficiency_pct cpu_peak_efficiency_pct <<<"${stats}"

  memory_utilization_pct="$(calc_utilization_pct "${max_mem_gb}" "${requested_memory_gb}")"
  [[ "${exit_code}" == "-" ]] && exit_code=""

  row="${RUN_ID},${module},${call_alias},${job_id},${lsf_status},${requested_cpu},${requested_memory_gb},${requested_lsf_queue},${max_mem_gb},${avg_mem_gb},${memory_utilization_pct},${lsf_mem_efficiency_pct},${cpu_time_sec},${wall_time_sec},${cpu_avg_efficiency_pct},${cpu_peak_efficiency_pct},${exit_code}"
  echo "${row}" >> "${OUTPUT}"

  jq -n \
    --arg run_id "${RUN_ID}" \
    --arg module_name "${module}" \
    --arg call_alias "${call_alias}" \
    --arg lsf_job_id "${job_id}" \
    --arg lsf_status "${lsf_status}" \
    --argjson requested_cpu "$(json_number_or_null "${requested_cpu}")" \
    --argjson requested_memory_gb "$(json_number_or_null "${requested_memory_gb}")" \
    --arg requested_lsf_queue "${requested_lsf_queue}" \
    --argjson actual_max_memory_gb "$(json_number_or_null "${max_mem_gb}")" \
    --argjson actual_avg_memory_gb "$(json_number_or_null "${avg_mem_gb}")" \
    --argjson memory_utilization_pct "$(json_number_or_null "${memory_utilization_pct}")" \
    --argjson lsf_mem_efficiency_pct "$(json_number_or_null "${lsf_mem_efficiency_pct}")" \
    --argjson cpu_time_sec "$(json_number_or_null "${cpu_time_sec}")" \
    --argjson wall_time_sec "$(json_number_or_null "${wall_time_sec}")" \
    --argjson cpu_avg_efficiency_pct "$(json_number_or_null "${cpu_avg_efficiency_pct}")" \
    --argjson cpu_peak_efficiency_pct "$(json_number_or_null "${cpu_peak_efficiency_pct}")" \
    --arg lsf_exit_code "${exit_code}" \
    '{
      run_id: $run_id,
      module: $module_name,
      call_alias: $call_alias,
      lsf_job_id: $lsf_job_id,
      lsf_status: $lsf_status,
      requested: {
        cpu: $requested_cpu,
        memory_gb: $requested_memory_gb,
        lsf_queue: $requested_lsf_queue
      },
      actual: {
        max_memory_gb: $actual_max_memory_gb,
        avg_memory_gb: $actual_avg_memory_gb,
        cpu_time_sec: $cpu_time_sec,
        wall_time_sec: $wall_time_sec
      },
      efficiency: {
        memory_utilization_pct: $memory_utilization_pct,
        lsf_mem_efficiency_pct: $lsf_mem_efficiency_pct,
        cpu_avg_efficiency_pct: $cpu_avg_efficiency_pct,
        cpu_peak_efficiency_pct: $cpu_peak_efficiency_pct
      },
      lsf_exit_code: (if $lsf_exit_code == "" then null else $lsf_exit_code end)
    }' >> "${tmp_rows}"
done

if [[ "${module_count}" -eq 0 ]]; then
  echo "No module job_id files found under ${CALLS_DIR}" >&2
  exit 1
fi

if [[ "${WRITE_JSON}" -eq 1 ]]; then
  if [[ -s "${tmp_rows}" ]]; then
    jq -s \
    --arg generated_at "$(date -Is)" \
    --arg snap_root "${SNAP_ROOT}" \
    --arg run_id "${RUN_ID}" \
    --arg run_dir "${RUN_DIR}" \
  '{
    generated_at: $generated_at,
    snap_root: $snap_root,
    run_id: $run_id,
    run_dir: $run_dir,
    modules: .
  }' "${tmp_rows}" > "${JSON_OUTPUT}"
  fi
fi

echo "Wrote resource usage report: ${OUTPUT}"
[[ -f "${JSON_OUTPUT}" ]] && echo "Wrote resource usage JSON: ${JSON_OUTPUT}"
echo "  run_id: ${RUN_ID}"
echo "  modules with job_id: ${module_count}"
echo "  modules queried from LSF: ${queried_count}"
