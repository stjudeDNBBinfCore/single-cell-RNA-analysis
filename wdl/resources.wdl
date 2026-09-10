version 1.1

# Compute LSF + future.globals resources for downstream snap modules.
# Baseline: 8 samples x 50,000 cells (snap pipeline defaults).

workflow compute_snap_downstream_resources {
  input {
    Int num_samples = 8
    Int estimated_cells_per_sample = 50000
    String resource_tier = "auto"
  }

  Int baseline_samples = 8
  Int baseline_cells_per_sample = 50000
  Int total_cells = num_samples * estimated_cells_per_sample
  Int baseline_total_cells = baseline_samples * baseline_cells_per_sample

  Int sample_scale = if num_samples > baseline_samples then ((num_samples + baseline_samples - 1) / baseline_samples) else 1
  Int cell_scale = if total_cells > baseline_total_cells then ((total_cells + baseline_total_cells - 1) / baseline_total_cells) else 1
  Int scale = if sample_scale > cell_scale then sample_scale else cell_scale

  Int upstream_cpu = if num_samples <= 4 then 8 else if num_samples <= 12 then 16 else 24
  Int upstream_memory_gb = 30 + (cell_scale - 1) * 10
  Int upstream_future_globals_gib = 200 + (cell_scale - 1) * 50

  Int integrative_cpu = if num_samples <= 8 then 10 else 16
  Int integrative_memory_gb = 96 + (cell_scale - 1) * 24
  Int integrative_future_globals_gib = 200 + (cell_scale - 1) * 50

  Int cluster_cpu = if scale <= 1 then 4 else if scale <= 2 then 8 else 12
  Int cluster_memory_gb = 48 + (cell_scale - 1) * 16
  Int cluster_future_globals_gib = 400 + (cell_scale - 1) * 100

  Int contamination_memory_gb = 96 + (cell_scale - 1) * 24
  Int contamination_future_globals_gib = 400 + (cell_scale - 1) * 100

  Int cell_types_memory_gb = 64 + (cell_scale - 1) * 16

  Int de_go_memory_gb = 32 + (cell_scale - 1) * 8
  Int de_go_future_globals_gib = 200 + (cell_scale - 1) * 50

  String default_queue = if integrative_memory_gb >= 512 then "large_mem" else "standard"

  String resolved_tier = if resource_tier == "auto" then (
    if scale <= 1 then "default" else if scale <= 2 then "large" else "xlarge"
  ) else resource_tier

  output {
    Int out_num_samples = num_samples
    Int out_total_cells = total_cells
    String out_resource_tier = resolved_tier
    Int out_scale_factor = scale

    Int out_upstream_cpu = upstream_cpu
    Int out_upstream_memory_gb = upstream_memory_gb
    Int out_upstream_future_globals_gib = upstream_future_globals_gib

    Int out_integrative_cpu = integrative_cpu
    Int out_integrative_memory_gb = integrative_memory_gb
    Int out_integrative_future_globals_gib = integrative_future_globals_gib

    Int out_cluster_cpu = cluster_cpu
    Int out_cluster_memory_gb = cluster_memory_gb
    Int out_cluster_future_globals_gib = cluster_future_globals_gib

    Int out_contamination_memory_gb = contamination_memory_gb
    Int out_contamination_future_globals_gib = contamination_future_globals_gib

    Int out_cell_types_memory_gb = cell_types_memory_gb

    Int out_de_go_memory_gb = de_go_memory_gb
    Int out_de_go_future_globals_gib = de_go_future_globals_gib

    String out_lsf_queue = default_queue
  }
}
