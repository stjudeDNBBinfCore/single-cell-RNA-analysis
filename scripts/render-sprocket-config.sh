#!/usr/bin/env bash
# Write inputs/sprocket.generated.toml (copy of base config for launch-time overrides).
set -euo pipefail

SNAP_ROOT="${1:-}"
INPUTS="${2:-}"

if [[ -z "${SNAP_ROOT}" ]]; then
  echo "Usage: render-sprocket-config.sh SNAP_ROOT [SPROCKET_INPUTS_JSON]" >&2
  exit 1
fi

SNAP_ROOT="$(cd "${SNAP_ROOT}" && pwd)"
BASE_CONFIG="${SNAP_ROOT}/sprocket.toml"
OUT_CONFIG="${SNAP_ROOT}/inputs/sprocket.generated.toml"
INPUTS="${INPUTS:-${SNAP_ROOT}/inputs/sprocket_inputs.json}"

if [[ ! -f "${BASE_CONFIG}" ]]; then
  echo "Missing ${BASE_CONFIG}" >&2
  exit 1
fi

mkdir -p "${SNAP_ROOT}/inputs"
cp "${BASE_CONFIG}" "${OUT_CONFIG}"

NOTIFY_EMAIL=""
if [[ -f "${INPUTS}" ]]; then
  NOTIFY_EMAIL="$(
    grep -o '"sc_rna_seq_snap_downstream.notify_email"[[:space:]]*:[[:space:]]*"[^"]*"' "${INPUTS}" \
      | sed -n '1s/.*"\([^"]*\)"$/\1/p'
  )"
fi

echo "Wrote ${OUT_CONFIG}${NOTIFY_EMAIL:+ (module emails via monitor → ${NOTIFY_EMAIL})}"
