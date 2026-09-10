# sc-rna-seq-snap downstream (WDL + Sprocket)

Run downstream snap modules (upstream-analysis onwards) on St. Jude HPC via **Sprocket** and **WDL**. Resources are estimated from your sample count and Cell Ranger metrics; module toggles and biology parameters come from YAML.

**Background:** [resources-snap.md](../../../docs/resources-snap.md) · [resources-sprocket.md](../../../docs/resources-sprocket.md) · [learning path](../../../docs/learning-path-wdl-sprocket-containers.md)

## Prerequisites

Before launching downstream:

1. **FastQC** and **Cell Ranger** are complete under `analyses/cellranger-analysis/`.
2. **Sample metadata** exists at `data/project_metadata/project_metadata.tsv`.
3. **Apptainer/Singularity image** is present at the project root (default name: `rstudio_4.4.0_seurat_4.4.0_latest.sif`).
4. You are on a St. Jude HPC node with **Sprocket** and **R** available.

## Load modules

```bash
module load sprocket R singularity
```


## Quick start

Run from the **project root** (parent of this `scripts/` folder):

```bash
# Dry-run: regenerate WDL/YAML/inputs, validate (no LSF submit)
bash launch-snap-downstream.sh
```

---

## Safe ways to run it

### Option 1 — nohup in the background (recommended)

```
nohup bash launch-snap-downstream.sh --no-call-cache --submit > snap-launch.log 2>&1 &
echo $!   # note the PID
```

Monitor progress:

```
tail -f snap-launch.log
```

or

```
tail -f out/runs/sc_rna_seq_snap_downstream/_latest/calls/upstream/attempts/0/stderr
```


### Option 2 — tmux or screen 

```
tmux new -s snap
module load sprocket R singularity
bash launch-snap-downstream.sh

bash launch-snap-downstream.sh --submit
# Detach: Ctrl+b then d
# Reattach later: tmux attach -t snap
```


# Which modules to run via WDL/Sprocket (all optional).
# Toggle any combination; each enabled module waits on the last completed step.
# FastQC and Cell Ranger run in parallel with fixed LSF resources (never scaled).
# Upstream waits on Cell Ranger if enabled, else FastQC.


---

## What the launcher does

Each run performs these steps in order:

| Step | Script | Output |
|------|--------|--------|
| 1. Generate WDL | `scripts/generate-snap-wdl.R` | `wdl/snap.wdl` |
| 2. Estimate resources | `scripts/estimate-snap-downstream-resources.R` | `inputs/project_parameters.generated.yaml`, `inputs/generated_downstream.json`, `inputs/sprocket_inputs.json` |
| 3. Check WDL | `sprocket check wdl/snap.wdl` | — |
| 4. Validate inputs | `sprocket validate wdl/snap.wdl @inputs/sprocket_inputs.json` | — |
| 5. Submit (if not dry-run) | `sprocket run ...` | LSF jobs |

The resource estimator:

- Counts samples from `project_metadata.tsv` (or Cell Ranger output directories).
- Reads **Cell Ranger** `metrics_summary.csv` for cells per sample.
- Scales LSF CPU, memory, queue, and `future_globals_*` values (baseline: 8 samples × 50k cells).
- Adds **20% LSF memory headroom** to every module’s `*_memory_gb` value (via `apply_lsf_memory_headroom()` in `estimate-snap-downstream-resources.R`) so jobs are not killed when usage spikes slightly above the base estimate. Example: upstream base **30 GB** → **36 GB** requested on LSF (`ceil(30 × 1.2)`).
- Copies **workflow module toggles** from `workflow_profile` in your master YAML into Sprocket inputs.

At runtime, downstream R modules load config via `scripts/snap_read_config.R` (see [YAML config: which file is used?](#yaml-config-which-file-is-used) below).

---

## YAML config: which file is used?

The pipeline supports **three ways to run** downstream modules. The config file is chosen automatically — you do not pick it in the YAML itself.

| How you launch | Launcher | Config file used |
|----------------|----------|------------------|
| **WDL / Sprocket** | `bash launch-snap-downstream.sh --submit` or `bash scripts/launch-snap-sprocket.sh` | `inputs/project_parameters.generated.yaml` |
| **Full LSF chain** | `bash launch_full_pipeline.sh` | `project_parameters.Config.yaml` |
| **Interactive / per-module LSF** | Run `analyses/<module>/run-*.sh` or `Rscript run-*.R` directly | `project_parameters.Config.yaml` |

### How it works

- **WDL/Sprocket** sets `SNAP_CONFIG_FILE` in each task (`wdl/tasks.wdl`) to the generated overlay. Module scripts detect this and load the generated YAML (scaled resources + paths refreshed at launch).
- **All other run modes** do not set `SNAP_CONFIG_FILE`, so modules load the master template `project_parameters.Config.yaml`.
- **FastQC and Cell Ranger** are unchanged: they still read `project_parameters.Config.yaml` directly (grep in shell scripts). They run before the WDL downstream workflow.

### Helpers (R and bash)

| File | Use |
|------|-----|
| `scripts/snap_read_config.R` | `snap_load_project_config()`, `snap_read_master_config()`, `snap_is_wdl_run()` |
| `scripts/snap-read-config.sh` | `snap_yaml_get`, `snap_yaml_list`, `snap_log_config_file` |

**R module entry scripts** (upstream onwards) use:

```r
snap_root <- normalizePath("../..", winslash = "/")
source(file.path(snap_root, "scripts", "snap_read_config.R"))
yaml <- snap_load_project_config(snap_root)   # prints: Using config: <path>
```

**Bash module scripts** (e.g. clone-phylogeny) use:

```bash
SNAP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SNAP_ROOT}/scripts/snap-read-config.sh"
snap_log_config_file
root_dir="$(snap_yaml_get root_dir)"
```

### Manual override

To force a specific YAML (e.g. test the generated overlay outside Sprocket):

```bash
export SNAP_CONFIG_FILE=/path/to/snap/inputs/project_parameters.generated.yaml
Rscript analyses/upstream-analysis/run-upstream-analysis.R
```

### What to edit

| File | When to edit |
|------|----------------|
| `project_parameters.Config.yaml` | Biology, paths, `workflow_profile`, emails — **always edit this** for interactive/LSF runs |
| `inputs/project_parameters.generated.yaml` | **Do not edit by hand** — regenerated by `estimate-snap-downstream-resources.R` on each Sprocket launch |

---

## Files you edit manually

### 1. `project_parameters.Config.yaml` (master template — **edit this**)

This is your main configuration file. The launcher **does not overwrite** it by default; it writes a generated overlay instead.

**Always review/update before launch:**

| Section | What to set |
|---------|-------------|
| Project paths | `root_dir`, `data_dir`, `metadata_dir` — use absolute paths for your project (estimator refreshes these on each run). |
| `workflow_profile` | Turn modules on/off (`run_upstream`, `run_integrative`, `run_cluster`, etc.). |
| `resource_profile.container_image` | Full path to the Seurat Apptainer `.sif` if not at `<root_dir>/rstudio_4.4.0_seurat_4.4.0_latest.sif`. |
| Biology / QC | Upstream filters (`min_genes`, `min_count`, `condition_value*`), integration method, clustering resolution, annotation method, etc. |
| Module-specific | Sections for integrative, cluster, contamination, cell-types, clone-phylogeny, de-go, rshiny — see inline comments in the YAML. |

**Example — upstream only:**

```yaml
workflow_profile:
  run_upstream: true
  run_integrative: false
  run_cluster: false
  run_contamination_removal: false
  run_cell_types: false
  run_clone_phylogeny: false
  run_de_go: false
  run_rshiny: false
```

**Example — enable more modules later:**

Set the relevant `run_*` keys to `true`, then re-run `bash launch-snap-downstream.sh --submit`.

Optional resource overrides (usually leave as `null` so Cell Ranger metrics drive scaling):

```yaml
resource_profile:
  num_samples: null                  # null = auto-count
  estimated_cells_per_sample: null   # null = mean from Cell Ranger
  resource_tier: "default"
  container_image: "/full/path/to/rstudio_4.4.0_seurat_4.4.0_latest.sif"
```

### 2. `data/project_metadata/project_metadata.tsv`

Define samples, FASTQ paths, and optional metadata columns (`condition`, etc.). Required columns: `ID`, `SAMPLE`, `FASTQ`.

### 3. `sprocket.toml` (optional)

Default LSF backend settings (queue, concurrency, job prefix). Usually fine as-is. Edit if you need a different queue or concurrency limits. The **container image** is passed per-task from YAML/workflow inputs, not from `sprocket.toml`.

### 4. Supporting data files (when those modules are enabled)

Examples:

- Gene markers / palettes under `data/` and `.figures/palettes/`
- Reference `.rds` for cell-type annotation
- Clone-phylogeny sample list in YAML

---

## Files you should **not** edit by hand

These are regenerated on each launch:

| File | Reason |
|------|--------|
| `wdl/snap.wdl` | Auto-generated; nested optional modules require the generator |
| `inputs/project_parameters.generated.yaml` | Runtime config overlay (master + scaled resources) |
| `inputs/generated_downstream.json` | Resource estimate snapshot |
| `inputs/sprocket_inputs.json` | Flat inputs for `sprocket validate` / `sprocket run` |

To change WDL structure, edit `scripts/generate-snap-wdl.R` and re-run the launcher.

---

## Scripts in this folder

| Script | Purpose |
|--------|---------|
| `launch-snap-sprocket.sh` | Main orchestrator (WDL gen → estimate → check → validate → run) |
| `generate-snap-wdl.R` | Builds `wdl/snap.wdl` with all modules optional |
| `estimate-snap-downstream-resources.R` | Cell Ranger metrics → LSF resources + YAML/JSON |
| `render-sprocket-config.sh` | Writes `inputs/sprocket.generated.toml` for launch |
| `monitor-snap-task-emails.sh` | Background per-module start/complete emails while Sprocket runs |
| `snap-notify-email.sh` | Sends workflow/module email notifications (login node) |
| `snap_read_config.R` | Helper used by R modules to load YAML config |
| `snap-read-config.sh` | Bash helper for shell scripts (same config precedence as `snap_read_config.R`) |
| `collect-snap-resource-usage.sh` | Post-run LSF resource report (requested vs actual per module) |
| `test-downstream-layout.sh` | Sanity-check that expected WDL/inputs files exist |

Root launcher (one level up): `launch-snap-downstream.sh`

---

## Advanced options

**Estimate resources only (no Sprocket):**

```bash
Rscript scripts/estimate-snap-downstream-resources.R \
  --snap-root . \
  --output inputs/generated_downstream.json \
  --update-yaml
```

**Override cell count** (if Cell Ranger metrics are missing):

```bash
Rscript scripts/estimate-snap-downstream-resources.R \
  --snap-root . \
  --estimated-cells-per-sample 8208 \
  --output inputs/generated_downstream.json \
  --update-yaml
```

**Overwrite master YAML in place** (creates `project_parameters.Config.yaml.orig` backup):

```bash
bash scripts/launch-snap-sprocket.sh --snap-root . --yaml-in-place --dry-run
```

**Skip YAML refresh:**

```bash
bash scripts/launch-snap-sprocket.sh --snap-root . --no-update-yaml --dry-run
```

**Skip post-run resource report:**

```bash
bash scripts/launch-snap-sprocket.sh --snap-root . --no-resource-report --submit
```

---

## Resource usage (requested vs actual)

After each Sprocket run, the launcher calls `scripts/collect-snap-resource-usage.sh` to compare **requested** LSF resources (from task `inputs.json`) with **actual** usage from LSF (`bjobs`).

Reports are written to:

```
out/resource_usage/resource_usage_<run_id>.csv
out/resource_usage/resource_usage_<run_id>.json
```

Key columns: `requested_cpu`, `requested_memory_gb`, `actual_max_memory_gb`, `memory_utilization_pct`, `cpu_time_sec`, `wall_time_sec`, `cpu_avg_efficiency_pct`.

**Run manually** (e.g. after an older run):

```bash
# Latest Sprocket run
bash scripts/collect-snap-resource-usage.sh --snap-root . --latest --json

# Specific run
bash scripts/collect-snap-resource-usage.sh --snap-root . --run-id 2026-08-31_234355266651904
```

**Requested resources only** (pre-run estimates, not actual usage):

| File | Contents |
|------|----------|
| `inputs/generated_downstream.json` | Full estimate snapshot + Sprocket inputs |
| `inputs/sprocket_inputs.json` | Flat inputs passed to `sprocket run` |

---

## Downstream modules

| Module | YAML toggle | WDL task |
|--------|-------------|----------|
| Upstream QC / Seurat | `run_upstream` | `run_upstream` |
| Integrative (Harmony, etc.) | `run_integrative` | `run_integrative` |
| Cluster / markers | `run_cluster` | `run_cluster` |
| Contamination removal | `run_contamination_removal` | `run_contamination` |
| Cell-type annotation | `run_cell_types` | `run_cell_types` |
| Clone phylogeny | `run_clone_phylogeny` | `run_clone_phylogeny` |
| DE / GO | `run_de_go` | `run_de_go` |
| R Shiny app | `run_rshiny` | `run_rshiny` |

Enabled modules run in dependency order; skipped modules do not block later steps.

## Email notifications

Notifications go to **`CONTACT_EMAIL`** in `project_parameters.Config.yaml` (passed as `notify_email` in Sprocket inputs).

| When | How |
|------|-----|
| Workflow submitted | `launch-snap-sprocket.sh` → `snap-notify-email.sh` (login node) |
| Each module started | `monitor-snap-task-emails.sh` when LSF `job_id` appears for that module |
| Each module completed / failed | `monitor-snap-task-emails.sh` when LSF job reaches `DONE` / `EXIT` |
| Whole workflow finished / failed | Launch script after `sprocket run` exits |

Module emails use **`CONTACT_EMAIL`** from `project_parameters.Config.yaml`. The monitor runs in the background while Sprocket executes and polls `out/runs/sc_rna_seq_snap_downstream/_latest/calls/`.

To change the recipient, edit `CONTACT_EMAIL` in the master YAML and re-run the launcher.

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `sprocket not found` | `module load sprocket` on an HPC node |
| `singularity: command not found` inside task | Load singularity before launch: `module load singularity`. Tasks must not call `singularity exec` manually — Sprocket wraps commands via `runtime.container`. |
| Missing Cell Ranger metrics | Complete Cell Ranger or pass `--estimated-cells-per-sample` |
| Container pull fails / `repository name must be lowercase` | Local `.sif` paths must use the `file://` scheme for Sprocket (auto-added in `sprocket_inputs.json`). Keep plain paths in YAML; re-run the launcher to regenerate inputs. |
| Wrong modules running | Edit `workflow_profile` in `project_parameters.Config.yaml`, then re-launch |
| LSF job killed at memory limit (`TERM_MEMLIMIT`) | Re-run the launcher so `estimate-snap-downstream-resources.R` refreshes `inputs/sprocket_inputs.json` with the 20% headroom applied. If a module still OOMs, increase the base tier manually in `compute_resources()` or reduce parallel work inside that R module. |

Monitor LSF jobs after submit:

```bash
bjobs -u $USER
```

---

## Legacy path (not recommended)

`launch_full_pipeline.sh` uses static LSF bash scripts under `analyses/*/lsf-script.txt` and reads **`project_parameters.Config.yaml`** only (not the generated overlay). FastQC and Cell Ranger also read the master YAML directly. For dynamic scaling and optional modules via WDL, use **`launch-snap-downstream.sh`** instead.
