#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SNAP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "==> Snap root: ${SNAP_ROOT}"
echo

required=(
  wdl/snap.wdl
  wdl/tasks.wdl
  wdl/resources.wdl
  wdl/snap_multi_project.wdl
  sprocket.toml
  inputs/downstream_test_3modules.json
  inputs/downstream_example.json
  scripts/estimate-snap-downstream-resources.R
  scripts/launch-snap-sprocket.sh
)

for f in "${required[@]}"; do
  [[ -e "${SNAP_ROOT}/${f}" ]] && echo "OK      ${f}" || { echo "MISSING: ${f}"; exit 1; }
done

echo
echo "==> Downstream modules in workflow"
grep -E "^task run_" "${SNAP_ROOT}/wdl/tasks.wdl" | sed 's/task /  /'

echo
echo "==> Resource scaling preview (baseline 8 x 50k cells)"
printf "%-8s %-10s %-12s %-12s %-10s\n" "samples" "tier" "upstream_GB" "integrative_GB" "cluster_GB"
for samples in 8 16 24; do
  cells=50000
  total=$((samples * cells))
  base=$((8 * 50000))
  cs=$(( (total + base - 1) / base )); cs=$(( cs < 1 ? 1 : cs ))
  ss=$(( (samples + 7) / 8 )); ss=$(( ss < 1 ? 1 : ss ))
  scale=$(( ss > cs ? ss : cs ))
  tier=$([[ $scale -le 1 ]] && echo default || ([[ $scale -le 2 ]] && echo large || echo xlarge))
  up=$((30 + (cs - 1) * 10))
  integ=$((96 + (cs - 1) * 24))
  clust=$((48 + (cs - 1) * 16))
  printf "%-8s %-10s %-12s %-12s %-10s\n" "$samples" "$tier" "$up" "$integ" "$clust"
done

echo
echo "Next: module load sprocket R && bash scripts/launch-snap-sprocket.sh --snap-root \"${SNAP_ROOT}\" --dry-run"
