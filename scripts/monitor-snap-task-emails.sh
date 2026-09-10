#!/usr/bin/env bash
# Poll Sprocket run directories and email CONTACT_EMAIL on module start/complete.
#
# Usage:
#   monitor-snap-task-emails.sh --snap-root PATH --to EMAIL --watch-pid PID [--interval SEC]

set -euo pipefail

SNAP_ROOT=""
NOTIFY_EMAIL=""
WATCH_PID=""
INTERVAL=30
NOTIFY_SCRIPT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --snap-root) SNAP_ROOT="$2"; shift 2 ;;
    --to) NOTIFY_EMAIL="$2"; shift 2 ;;
    --watch-pid) WATCH_PID="$2"; shift 2 ;;
    --interval) INTERVAL="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,5p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

[[ -n "${SNAP_ROOT}" && -n "${NOTIFY_EMAIL}" && -n "${WATCH_PID}" ]] || {
  echo "Usage: monitor-snap-task-emails.sh --snap-root PATH --to EMAIL --watch-pid PID" >&2
  exit 1
}

NOTIFY_SCRIPT="${SNAP_ROOT}/scripts/snap-notify-email.sh"
RUNS_ROOT="${SNAP_ROOT}/out/runs/sc_rna_seq_snap_downstream"
STATE_DIR="${SNAP_ROOT}/inputs"

send_module_email() {
  local subject="$1"
  local body="$2"
  bash "${NOTIFY_SCRIPT}" --to "${NOTIFY_EMAIL}" --subject "${subject}" --body "${body}" || true
}

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

module_label() {
  local module="$1"
  case "${module}" in
    upstream) echo "Upstream analysis" ;;
    integrative) echo "Integrative analysis" ;;
    cluster) echo "Cluster cell calling" ;;
    contamination_removal) echo "Contamination removal" ;;
    cell_types) echo "Cell types annotation" ;;
    clone_phylogeny) echo "Clone phylogeny" ;;
    de_go) echo "DE/GO analysis" ;;
    rshiny) echo "R Shiny app" ;;
    *) echo "${module}" ;;
  esac
}

state_file_for_run() {
  local run_id="$1"
  echo "${STATE_DIR}/.snap-module-email-state-${run_id}"
}

is_marked() {
  local state_file="$1"
  local key="$2"
  [[ -f "${state_file}" ]] && grep -Fxq "${key}" "${state_file}"
}

mark() {
  local state_file="$1"
  local key="$2"
  mkdir -p "${STATE_DIR}"
  echo "${key}" >> "${state_file}"
}

resolve_calls_dir() {
  local latest_link="${RUNS_ROOT}/_latest"
  if [[ -L "${latest_link}" || -d "${latest_link}" ]]; then
    local target
    target="$(readlink -f "${latest_link}" 2>/dev/null || echo "${latest_link}")"
    if [[ -d "${target}/calls" ]]; then
      echo "${target}/calls"
      return 0
    fi
  fi
  local newest
  newest="$(find "${RUNS_ROOT}" -mindepth 1 -maxdepth 1 -type d ! -name '_latest' -printf '%T@ %p\n' 2>/dev/null \
    | sort -nr | head -1 | awk '{print $2}')"
  if [[ -n "${newest}" && -d "${newest}/calls" ]]; then
    echo "${newest}/calls"
    return 0
  fi
  return 1
}

job_lsf_status() {
  local job_id="$1"
  local line
  line="$(bjobs -noheader -o stat "${job_id}" 2>/dev/null | head -1 | tr -d '[:space:]')"
  if [[ -n "${line}" ]]; then
    echo "${line}"
    return 0
  fi
  line="$(bjobs -a -noheader -o stat "${job_id}" 2>/dev/null | head -1 | tr -d '[:space:]')"
  if [[ -n "${line}" ]]; then
    echo "${line}"
    return 0
  fi
  echo "UNKNOWN"
}

while kill -0 "${WATCH_PID}" 2>/dev/null; do
  if calls_dir="$(resolve_calls_dir 2>/dev/null)"; then
    run_id="$(basename "$(dirname "${calls_dir}")")"
    state_file="$(state_file_for_run "${run_id}")"

    for call_path in "${calls_dir}"/*/; do
      [[ -d "${call_path}" ]] || continue
      alias="$(basename "${call_path}")"
      module="$(normalize_module "${alias}")"
      label="$(module_label "${module}")"
      attempt_dir="${call_path}attempts/0"
      job_id_file="${attempt_dir}/job_id"

      if [[ -f "${job_id_file}" ]]; then
        job_id="$(tr -d '[:space:]' < "${job_id_file}")"
        start_key="${module}:started"

        if ! is_marked "${state_file}" "${start_key}"; then
          send_module_email \
            "[snap] ${module}: started" \
            "${label} started at $(date -Is)\nLSF job: ${job_id}\nProject: ${SNAP_ROOT}"
          mark "${state_file}" "${start_key}"
        fi

        complete_key="${module}:completed"
        fail_key="${module}:failed"
        if ! is_marked "${state_file}" "${complete_key}" && ! is_marked "${state_file}" "${fail_key}"; then
          status="$(job_lsf_status "${job_id}")"
          case "${status}" in
            DONE)
              send_module_email \
                "[snap] ${module}: completed" \
                "${label} completed successfully at $(date -Is)\nLSF job: ${job_id}\nProject: ${SNAP_ROOT}"
              mark "${state_file}" "${complete_key}"
              ;;
            EXIT|ZOMBI|UNKWN)
              send_module_email \
                "[snap] ${module}: failed" \
                "${label} failed (LSF status: ${status}) at $(date -Is)\nLSF job: ${job_id}\nProject: ${SNAP_ROOT}\nCheck: ${attempt_dir}/stderr"
              mark "${state_file}" "${fail_key}"
              ;;
          esac
        fi
      fi
    done
  fi
  sleep "${INTERVAL}"
done

# Final poll after sprocket exits (catch jobs that finished at the end).
if calls_dir="$(resolve_calls_dir 2>/dev/null)"; then
  run_id="$(basename "$(dirname "${calls_dir}")")"
  state_file="$(state_file_for_run "${run_id}")"
  for call_path in "${calls_dir}"/*/; do
    [[ -d "${call_path}" ]] || continue
    alias="$(basename "${call_path}")"
    module="$(normalize_module "${alias}")"
    label="$(module_label "${module}")"
    attempt_dir="${call_path}attempts/0"
    job_id_file="${attempt_dir}/job_id"
    [[ -f "${job_id_file}" ]] || continue
    job_id="$(tr -d '[:space:]' < "${job_id_file}")"
    complete_key="${module}:completed"
    fail_key="${module}:failed"
    if is_marked "${state_file}" "${complete_key}" || is_marked "${state_file}" "${fail_key}"; then
      continue
    fi
    status="$(job_lsf_status "${job_id}")"
    case "${status}" in
      DONE)
        send_module_email \
          "[snap] ${module}: completed" \
          "${label} completed successfully at $(date -Is)\nLSF job: ${job_id}\nProject: ${SNAP_ROOT}"
        mark "${state_file}" "${complete_key}"
        ;;
      EXIT|ZOMBI|UNKWN|UNKNOWN)
        send_module_email \
          "[snap] ${module}: failed" \
          "${label} failed (LSF status: ${status}) at $(date -Is)\nLSF job: ${job_id}\nProject: ${SNAP_ROOT}\nCheck: ${attempt_dir}/stderr"
        mark "${state_file}" "${fail_key}"
        ;;
    esac
  done
fi
