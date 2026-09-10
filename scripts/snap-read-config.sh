#!/usr/bin/env bash
# Resolve snap YAML config (same precedence as scripts/snap_read_config.R).
#
# Usage from a module script under analyses/<module>/:
#   SNAP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
#   # shellcheck source=../../scripts/snap-read-config.sh
#   source "${SNAP_ROOT}/scripts/snap-read-config.sh"
#   root_dir="$(snap_yaml_get root_dir)"

snap_resolve_root() {
  if [[ -n "${SNAP_ROOT:-}" ]]; then
    echo "${SNAP_ROOT}"
    return 0
  fi
  if [[ -n "${BASH_SOURCE[1]:-}" ]]; then
    cd "$(dirname "${BASH_SOURCE[1]}")/../.." && pwd
    return 0
  fi
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

snap_config_file() {
  local snap_root
  snap_root="$(snap_resolve_root)"
  if [[ -n "${SNAP_CONFIG_FILE:-}" ]]; then
    if [[ -f "${SNAP_CONFIG_FILE}" ]]; then
      echo "${SNAP_CONFIG_FILE}"
      return 0
    fi
    echo "SNAP_CONFIG_FILE is set but not found: ${SNAP_CONFIG_FILE}" >&2
    return 1
  fi
  if [[ -f "${snap_root}/project_parameters.Config.yaml" ]]; then
    echo "${snap_root}/project_parameters.Config.yaml"
  else
    echo "No snap config found under ${snap_root}" >&2
    return 1
  fi
}

snap_log_config_file() {
  echo "Using config: $(snap_config_file)"
}

_snap_yaml_r() {
  local snap_root rcode
  snap_root="$(snap_resolve_root)"
  rcode="$1"
  Rscript --vanilla -e "
    source('${snap_root}/scripts/snap_read_config.R')
    cfg <- snap_read_config('${snap_root}')
    ${rcode}
  "
}

# Print a top-level scalar value.
snap_yaml_get() {
  local key="$1"
  _snap_yaml_r "
    val <- cfg[['${key}']]
    if (is.null(val) || length(val) == 0L) quit(status=1)
    if (is.logical(val)) {
      cat(ifelse(val, 'TRUE', 'FALSE'))
    } else if (is.list(val)) {
      quit(status=1)
    } else {
      cat(as.character(val[[1L]]))
    }
  "
}

# Print one line per list element (skips null/empty entries).
snap_yaml_list() {
  local key="$1"
  _snap_yaml_r "
    val <- cfg[['${key}']]
    if (is.null(val)) quit(status=1)
    if (is.list(val) && !is.data.frame(val)) {
      for (x in val) {
        if (!is.null(x) && nzchar(as.character(x))) cat(x, '\n', sep='')
      }
    } else if (length(val) > 1L) {
      for (x in val) cat(x, '\n', sep='')
    } else if (!is.null(val) && nzchar(as.character(val))) {
      cat(val)
    }
  "
}

# Sample IDs from config \`sample\` list, or ID column of project_metadata.tsv.
snap_sample_ids() {
  local ids
  ids="$(snap_yaml_list sample 2>/dev/null || true)"
  if [[ -n "${ids}" ]]; then
    printf '%s\n' "${ids}"
    return 0
  fi

  local metadata_dir metadata_file tsv
  metadata_dir="$(snap_yaml_get metadata_dir)"
  metadata_file="$(snap_yaml_get metadata_file)"
  tsv="${metadata_dir}/${metadata_file}"
  if [[ ! -f "${tsv}" ]]; then
    echo "No sample list in config and metadata not found: ${tsv}" >&2
    return 1
  fi
  tail -n +2 "${tsv}" | cut -f1
}
