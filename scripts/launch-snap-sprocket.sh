#!/usr/bin/env bash
set -euo pipefail

# Launch downstream snap workflow (upstream onwards) via Sprocket.
#
# Usage:
#   bash scripts/launch-snap-sprocket.sh [--snap-root PATH] [--no-update-yaml] [--yaml-in-place] [--dry-run] [--no-call-cache] [--no-resource-report]
#
# --no-call-cache: force all WDL tasks to re-run (Sprocket otherwise reuses prior upstream results).
#
# --update-yaml (default): writes inputs/project_parameters.generated.yaml;
#   populates root_dir/data_dir/metadata_dir from snap-root and reads Cell Ranger metrics;
#   project_parameters.Config.yaml (your master template) is not modified.
# --yaml-in-place: overwrite master YAML (creates project_parameters.Config.yaml.orig first).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SNAP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
UPDATE_YAML=1
YAML_IN_PLACE=0
DRY_RUN=0
NO_CALL_CACHE=0
COLLECT_RESOURCES=1
INPUTS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --snap-root) SNAP_ROOT="$2"; shift 2 ;;
    --inputs) INPUTS="$2"; shift 2 ;;
    --update-yaml) UPDATE_YAML=1; shift ;;
    --no-update-yaml) UPDATE_YAML=0; shift ;;
    --yaml-in-place) YAML_IN_PLACE=1; UPDATE_YAML=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --no-call-cache) NO_CALL_CACHE=1; shift ;;
    --no-resource-report) COLLECT_RESOURCES=0; shift ;;
    -h|--help)
      echo "Usage: bash scripts/launch-snap-sprocket.sh [--snap-root PATH] [--no-update-yaml] [--yaml-in-place] [--dry-run] [--no-call-cache] [--no-resource-report]"
      exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

WDL_DIR="${SNAP_ROOT}/wdl"
WORKFLOW="${WDL_DIR}/snap.wdl"
CONFIG="${SNAP_ROOT}/sprocket.toml"
GENERATED_CONFIG="${SNAP_ROOT}/inputs/sprocket.generated.toml"
GENERATED="${SNAP_ROOT}/inputs/generated_downstream.json"
SPROCKET_INPUTS="${SNAP_ROOT}/inputs/sprocket_inputs.json"
NOTIFY_SCRIPT="${SCRIPT_DIR}/snap-notify-email.sh"

mkdir -p "${SNAP_ROOT}/inputs"

if ! command -v sprocket >/dev/null 2>&1; then
  echo "sprocket not found. On St. Jude HPC: module load sprocket"
  exit 1
fi

if ! command -v apptainer >/dev/null 2>&1 && ! command -v singularity >/dev/null 2>&1; then
  echo "apptainer/singularity not found. On St. Jude HPC: module load singularity"
  exit 1
fi

UPDATE_FLAG=()
[[ "${UPDATE_YAML}" -eq 1 ]] && UPDATE_FLAG=(--update-yaml)
[[ "${YAML_IN_PLACE}" -eq 1 ]] && UPDATE_FLAG+=(--yaml-in-place)

echo "==> Generating WDL (all modules optional)"
Rscript "${SCRIPT_DIR}/generate-snap-wdl.R" --output "${WORKFLOW}"

echo "==> Estimating downstream resources"
Rscript "${SCRIPT_DIR}/estimate-snap-downstream-resources.R" \
  --snap-root "${SNAP_ROOT}" \
  --output "${GENERATED}" \
  "${UPDATE_FLAG[@]}"

[[ -z "${INPUTS}" ]] && INPUTS="${SPROCKET_INPUTS}"

if [[ ! -f "${INPUTS}" ]]; then
  echo "Missing Sprocket inputs: ${INPUTS}" >&2
  echo "Re-run resource estimation or pass --inputs PATH" >&2
  exit 1
fi

echo "==> Rendering Sprocket config"
bash "${SCRIPT_DIR}/render-sprocket-config.sh" "${SNAP_ROOT}" "${INPUTS}"
CONFIG="${GENERATED_CONFIG}"
MONITOR_SCRIPT="${SCRIPT_DIR}/monitor-snap-task-emails.sh"
RESOURCE_SCRIPT="${SCRIPT_DIR}/collect-snap-resource-usage.sh"

NOTIFY_EMAIL="$(
  grep -o '"sc_rna_seq_snap_downstream.notify_email"[[:space:]]*:[[:space:]]*"[^"]*"' "${INPUTS}" \
    | sed -n '1s/.*"\([^"]*\)"$/\1/p'
)"

send_workflow_email() {
  local subject="$1"
  local body="$2"
  bash "${NOTIFY_SCRIPT}" --to "${NOTIFY_EMAIL}" --subject "${subject}" --body "${body}" || true
}

echo "==> Checking WDL"
sprocket check "${WORKFLOW}"

echo "==> Validating inputs (${INPUTS})"
sprocket validate "${WORKFLOW}" @"${INPUTS}" --config "${CONFIG}"

[[ "${DRY_RUN}" -eq 1 ]] && { echo "Dry run complete."; exit 0; }

echo "==> Submitting downstream workflow"
send_workflow_email "[snap] workflow: submitted" \
  "Snap downstream workflow submitted at $(date -Is)\nProject: ${SNAP_ROOT}\nConfig: ${CONFIG}"

set +e
SPROCKET_RUN_FLAGS=(run "${WORKFLOW}" @"${INPUTS}" --config "${CONFIG}")
[[ "${NO_CALL_CACHE}" -eq 1 ]] && SPROCKET_RUN_FLAGS+=(--no-call-cache)
sprocket "${SPROCKET_RUN_FLAGS[@]}" &
SPROCKET_PID=$!

bash "${MONITOR_SCRIPT}" \
  --snap-root "${SNAP_ROOT}" \
  --to "${NOTIFY_EMAIL}" \
  --watch-pid "${SPROCKET_PID}" &
MONITOR_PID=$!

wait "${SPROCKET_PID}"
RUN_EXIT=$?

wait "${MONITOR_PID}" 2>/dev/null || true
set -e

if [[ "${COLLECT_RESOURCES}" -eq 1 ]]; then
  echo "==> Collecting per-module resource usage (requested vs actual)"
  bash "${RESOURCE_SCRIPT}" --snap-root "${SNAP_ROOT}" --latest --json || true
fi

if [[ "${RUN_EXIT}" -eq 0 ]]; then
  send_workflow_email "[snap] workflow: completed" \
    "Snap downstream workflow completed successfully at $(date -Is)\nProject: ${SNAP_ROOT}"
else
  send_workflow_email "[snap] workflow: failed" \
    "Snap downstream workflow failed (exit ${RUN_EXIT}) at $(date -Is)\nProject: ${SNAP_ROOT}\nCheck: ${SNAP_ROOT}/out/runs/sc_rna_seq_snap_downstream/"
fi
exit "${RUN_EXIT}"
