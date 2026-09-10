#!/usr/bin/env bash
set -euo pipefail

# Root launcher for downstream snap workflow (upstream-analysis onwards) via WDL + Sprocket.
#
# Prerequisites:
#   - FastQC and Cell Ranger complete under analyses/cellranger-analysis/
#   - module load sprocket R singularity   (on St. Jude HPC)
#   - Apptainer/Singularity image at rstudio_4.4.0_seurat_4.4.0_latest.sif
#
# Usage (from this directory):
#   bash launch-snap-downstream.sh              # dry-run: validate WDL + regenerate YAML/inputs
#   bash launch-snap-downstream.sh --submit     # submit to LSF via Sprocket
#
# What happens automatically:
#   1. Counts samples from project_metadata.tsv (or Cell Ranger output dirs)
#   2. Reads Cell Ranger metrics_summary.csv for cells/sample
#   3. Scales LSF cpu/memory/queue per module (baseline: 8 samples x 50k cells)
#   4. Writes inputs/project_parameters.generated.yaml (master Config.yaml unchanged)
#   5. Writes inputs/generated_downstream.json for Sprocket
#
# Edit project_parameters.Config.yaml for biology parameters and workflow_profile toggles.

SNAP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBMIT=0
EXTRA=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --submit) SUBMIT=1; shift ;;
    --dry-run) EXTRA+=(--dry-run); shift ;;
    -h|--help)
      sed -n '2,22p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *) EXTRA+=("$1"); shift ;;
  esac
done

if [[ "${SUBMIT}" -eq 0 && " ${EXTRA[*]:-} " != *" --dry-run "* ]]; then
  EXTRA+=(--dry-run)
fi

exec bash "${SNAP_ROOT}/scripts/launch-snap-sprocket.sh" \
  --snap-root "${SNAP_ROOT}" \
  --update-yaml \
  "${EXTRA[@]}"
