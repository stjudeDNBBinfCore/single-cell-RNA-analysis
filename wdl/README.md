# sc-rna-seq-snap WDL + Sprocket (downstream: upstream onwards)

Resource-aware orchestration for snap modules **from upstream-analysis through rshiny-app**, using [Sprocket](https://sprocket.bio/overview.html) and WDL. FastQC and Cell Ranger are assumed complete before launch.

Working implementation lives here; the design sketch is in `../mock-examples-code-wld-sprocket-v2/`.

## Scope

| Module | YAML future.globals key | Default LSF |
|--------|-------------------------|-------------|
| upstream-analysis | `future_globals_value_upstream` | 16 cpu / 30 GB |
| integrative-analysis | `future_globals_value_integrative` | 10 cpu / 96 GB |
| cluster-cell-calling | `future_globals_value_clustering` | 4 cpu / 48 GB |
| cell-contamination-removal | `future_globals_value_contamination` | 8 cpu / 96 GB |
| cell-types-annotation | — | 4 cpu / 64 GB |
| clone-phylogeny-analysis | — | 16 cpu / 30 GB |
| de-go-analysis | `future_globals_value_dego` | 4 cpu / 32 GB |
| rshiny-app | — | 4 cpu / 30 GB |

## Layout

```
wdl/
  snap.wdl                      # workflow: sc_rna_seq_snap_downstream
  snap_multi_project.wdl        # scatter multiple projects
  tasks.wdl                     # task wrappers
  resources.wdl                 # resource calculator
scripts/
  estimate-snap-downstream-resources.R
  launch-snap-sprocket.sh
  test-downstream-layout.sh
inputs/
  downstream_test_3modules.json # test: upstream + integrative + cluster
  downstream_example.json       # full downstream chain
  multi_project_downstream.json
sprocket.toml
```

## Quick start (St. Jude HPC)

```bash
module load sprocket R
cd /path/to/sc-rna-seq-snap-KIDS26-Team15

# Layout check (no sprocket submit)
bash scripts/test-downstream-layout.sh

# Estimate + sync YAML future.globals
Rscript scripts/estimate-snap-downstream-resources.R \
  --snap-root "$(pwd)" \
  --output inputs/generated_downstream.json \
  --update-yaml

# Validate and submit (test 3 modules first)
sprocket check wdl/snap.wdl
sprocket validate wdl/snap.wdl -i inputs/downstream_test_3modules.json
sprocket run wdl/snap.wdl -i inputs/downstream_test_3modules.json --config sprocket.toml
```

## Test 3 modules (upstream → integrative → cluster)

Use `inputs/downstream_test_3modules.json` — all other modules toggled off. This is the recommended first test after Cell Ranger completes.

## Multi-project launch

```bash
sprocket run wdl/snap_multi_project.wdl \
  -i inputs/multi_project_downstream.json \
  --config sprocket.toml
```


## Before submitting

- Set real paths in inputs/*.json (snap_root, container_image)
- Update sprocket.toml container path and LSF queue/project
-  Ensure project_metadata.tsv exists (resource script counts samples from it)

sprocket is not on PATH in this environment — use module load sprocket on St. Jude HPC.

## Architecture

FastQC ────────┐
               ├──> Upstream (waits on Cell Ranger if enabled, else FastQC)
Cell Ranger ───┘


This matches `launch_full_pipeline.sh`: FastQC and Cell Ranger run in parallel; upstream chains after the last enabled upstream step.


## Dependency chain

```
Upstream → Integrative → Cluster → [Contamination] → Cell types → [Clone phylogeny] → DE/GO → R Shiny
```

Skipped modules are bypassed; the chain propagates the last completed step's done flag.

## Resource scaling

Baseline: **8 samples × 50,000 cells**. `estimate-snap-downstream-resources.R` scales LSF memory and writes matching `future_globals_value_*` keys into `project_parameters.Config.yaml` when run with `--update-yaml`.

## References

- Full-pipeline mock (v1): `../mock-examples-code-wld-sprocket-v1/`
- Downstream mock (v2): `../mock-examples-code-wld-sprocket-v2/`
