#################################################################################
# This will run the `02A-run-seurat-qc.Rmd` script for multiple samples/libraries
# and save html report separetely for each one of them
# https://pkgs.rstudio.com/rmarkdown/reference/render.html
#################################################################################
# Load library
suppressPackageStartupMessages({
  library(knitr)
  library(tidyverse)
  library(yaml)
  library(optparse)
})

#################################################################################
# Load config: WDL/Sprocket uses inputs/project_parameters.generated.yaml
# (SNAP_CONFIG_FILE is set in wdl/tasks.wdl). Interactive, LSF, and
# launch_full_pipeline.sh use project_parameters.Config.yaml.
snap_root <- normalizePath("../..", winslash = "/")
source(file.path(snap_root, "scripts", "snap_read_config.R"))
yaml <- snap_load_project_config(snap_root)

#################################################################################
# Set up directories and paths to file Inputs/Outputs
root_dir <- yaml$root_dir
metadata_dir <- yaml$metadata_dir
metadata_file <- yaml$metadata_file
analysis_dir <- file.path(root_dir, "analyses", "upstream-analysis") 

# File path to plots directory for seurat_qc
seurat_qc_plots_dir <-
  file.path(plots_dir, "02_Seurat_qc") 
if (!dir.exists(seurat_qc_plots_dir)) {
  dir.create(seurat_qc_plots_dir)
}

# Create seurat_results_dir
seurat_results_dir <- 
  file.path(module_results_dir, paste0("02_Seurat_qc"))
if (!dir.exists(seurat_results_dir)) {
  dir.create(seurat_results_dir)
}

#######################################################
# Read metadata file and define `sample_name`
project_metadata_file <- file.path(metadata_dir, metadata_file) # metadata input file

# Read metadata file and define `sample_name`
project_metadata <- read.csv(project_metadata_file, sep = "\t", header = TRUE)
sample_name <- unique(as.character(project_metadata$ID))
sample_name <- sort(sample_name, decreasing = FALSE)
print(sample_name)

#####################################################################################
# Run markdown script per each library
for (i in seq_along(sample_name)){

  # Create directory to save html reports
  samples_plots_dir <- file.path(seurat_qc_plots_dir, sample_name[i]) 
  if (!dir.exists(samples_plots_dir)) {
    dir.create(samples_plots_dir)}
    
  # Create results_dir per sample
  results_dir <- file.path(seurat_results_dir, sample_name[i])
  if (!dir.exists(results_dir)) {
    dir.create(results_dir)}
  
  # Render and save html
  rmarkdown::render("02A_run_seurat_qc.Rmd", 
                    output_dir = file.path(samples_plots_dir),
                    clean = TRUE, # using TRUE will clean intermediate files that are created during rendering
                    output_file = c(paste('Report-', 'seurat-qc', '-', sample_name[i], '-', Sys.Date(), sep = '')),
                    output_format = 'all',
                    params = list(use_condition_split = yaml$use_condition_split_seurat_multiple_samples,
                                  print_pdf = yaml$print_pdf_seurat_multiple_samples,

                                  data_dir = yaml$data_dir,
                                  grouping = yaml$grouping,
                                  genome_name = yaml$genome_name_upstream,
                                  Regress_Cell_Cycle_value = yaml$Regress_Cell_Cycle_value,
                                  assay = yaml$assay_seurat_qc,
                                  min_genes = yaml$min_genes, 
                                  min_count = yaml$min_count,
                                  mtDNA_pct_default = yaml$mtDNA_pct_default,
                                  normalize_method = yaml$normalize_method,
                                  num_pcs = yaml$num_pcs,
                                  num_dim = yaml$num_dim_seurat_qc,
                                  num_neighbors = yaml$num_neighbors_seurat_qc,
                                  nfeatures_value = yaml$nfeatures_value,
                                  prefix = yaml$prefix,
                                  use_miQC = yaml$use_miQC,
                                  use_only_step1 = yaml$use_only_step1,
                                  condition_value1 = yaml$condition_value1,
                                  condition_value2 = yaml$condition_value2,
                                  condition_value3 = yaml$condition_value3,
                                  PCA_Feature_List_value = yaml$PCA_Feature_List_value,
                                  use_SoupX_filtering = yaml$use_SoupX_filtering_seurat_qc,
                                  
                                  # the following parameters are the same across the module #
                                  PROJECT_NAME = yaml$PROJECT_NAME,
                                  PI_NAME = yaml$PI_NAME,
                                  TASK_ID = yaml$TASK_ID,
                                  PROJECT_LEAD_NAME = yaml$PROJECT_LEAD_NAME,
                                  DEPARTMENT = yaml$DEPARTMENT,
                                  LEAD_ANALYSTS = yaml$LEAD_ANALYSTS,
                                  GROUP_LEAD = yaml$GROUP_LEAD,
                                  CONTACT_EMAIL = yaml$CONTACT_EMAIL,
                                  PIPELINE = yaml$PIPELINE, 
                                  START_DATE = yaml$START_DATE,
                                  COMPLETION_DATE = yaml$COMPLETION_DATE))
  
}

#################################################################################
