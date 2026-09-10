version 1.1

import "snap.wdl" as snap

struct SnapDownstreamProjectRun {
  String project_name
  String snap_root
  String container_image
  String notify_email

  Boolean run_upstream = true
  Boolean run_integrative = true
  Boolean run_cluster = true
  Boolean run_contamination_removal = false
  Boolean run_cell_types = true
  Boolean run_clone_phylogeny = false
  Boolean run_de_go = true
  Boolean run_rshiny = true

  Int num_samples = 8
  Int estimated_cells_per_sample = 50000

  Int upstream_cpu = 16
  Int upstream_memory_gb = 30
  Int upstream_future_globals_gib = 200
  String upstream_lsf_queue = "standard"

  Int integrative_cpu = 10
  Int integrative_memory_gb = 96
  Int integrative_future_globals_gib = 200
  String integrative_lsf_queue = "standard"

  Int cluster_cpu = 4
  Int cluster_memory_gb = 48
  Int cluster_future_globals_gib = 400
  String cluster_lsf_queue = "standard"
}

# Launch multiple downstream snap workflows concurrently (multiple projects or pipelines).
workflow sc_rna_seq_snap_downstream_multi_project {
  meta {
    description: "Scatter downstream snap workflows across multiple projects"
  }

  input {
    Array[SnapDownstreamProjectRun] projects
  }

  scatter (project in projects) {
    call snap.sc_rna_seq_snap_downstream {
      input:
        snap_root = project.snap_root,
        container_image = project.container_image,
        notify_email = project.notify_email,
        run_upstream = project.run_upstream,
        run_integrative = project.run_integrative,
        run_cluster = project.run_cluster,
        run_contamination_removal = project.run_contamination_removal,
        run_cell_types = project.run_cell_types,
        run_clone_phylogeny = project.run_clone_phylogeny,
        run_de_go = project.run_de_go,
        run_rshiny = project.run_rshiny,
        num_samples = project.num_samples,
        estimated_cells_per_sample = project.estimated_cells_per_sample,
        upstream_cpu = project.upstream_cpu,
        upstream_memory_gb = project.upstream_memory_gb,
        upstream_future_globals_gib = project.upstream_future_globals_gib,
        upstream_lsf_queue = project.upstream_lsf_queue,
        integrative_cpu = project.integrative_cpu,
        integrative_memory_gb = project.integrative_memory_gb,
        integrative_future_globals_gib = project.integrative_future_globals_gib,
        integrative_lsf_queue = project.integrative_lsf_queue,
        cluster_cpu = project.cluster_cpu,
        cluster_memory_gb = project.cluster_memory_gb,
        cluster_future_globals_gib = project.cluster_future_globals_gib,
        cluster_lsf_queue = project.cluster_lsf_queue,
    }
  }

  output {
    Array[Int?] num_samples = sc_rna_seq_snap_downstream.cohort_num_samples
    Array[Int?] total_cells = sc_rna_seq_snap_downstream.cohort_total_estimated_cells
    Array[File?] upstream_done = sc_rna_seq_snap_downstream.upstream_done_flag
    Array[File?] cluster_done = sc_rna_seq_snap_downstream.cluster_done_flag
  }
}
