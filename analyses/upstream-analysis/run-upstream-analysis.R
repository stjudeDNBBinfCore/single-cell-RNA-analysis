#################################################################################
# This will run all scripts in the module
#################################################################################
# Load the Package with a Specific Library Path
#.libPaths("/home/user/R/x86_64-pc-linux-gnu-library/4.4")
#################################################################################
# Load library
suppressPackageStartupMessages({
  library(yaml)})

#################################################################################
# Load config: WDL/Sprocket uses inputs/project_parameters.generated.yaml
# (SNAP_CONFIG_FILE is set in wdl/tasks.wdl). Interactive, LSF, and
# launch_full_pipeline.sh use project_parameters.Config.yaml.
snap_root <- normalizePath("../..", winslash = "/")
source(file.path(snap_root, "scripts", "snap_read_config.R"))
yaml <- snap_load_project_config(snap_root)

#################################################################################
# Set up directories and paths to root_dir and analysis_dir
root_dir <- yaml$root_dir
analysis_dir <- file.path(root_dir, "analyses", "upstream-analysis") 

# File path to plots directory
plots_dir <- file.path(analysis_dir, "plots") 
if (!dir.exists(plots_dir)) {
  dir.create(plots_dir)
}

# Create module_results_dir
module_results_dir <- file.path(analysis_dir, paste0("results"))
if (!dir.exists(module_results_dir)) {
  dir.create(module_results_dir)
}

SoupX_dir <- file.path(analysis_dir, "plots", "01_SoupX") 
scDblFinder_dir <- file.path(analysis_dir, "plots", "03_scDblFinder") 
Filter_object_dir <- file.path(analysis_dir, "plots", "04_Filter_object") 
Final_summary_report_dir <- file.path(analysis_dir, "plots", "05_Final_summary_report")

################################################################################################################
# Run Rmd scripts to process data per method
################################################################################################################
future_globals_value <- as.numeric(yaml$future_globals_value_upstream) * 1024^3
################################################################################################################
# (1) Estimating and filtering out ambient mRNA (`empty droplets`)
rmarkdown::render('01_run_SoupX.Rmd', 
                   clean = FALSE,
                   output_dir = file.path(SoupX_dir),
                   output_file = paste('Report-', 'SoupX', '-', Sys.Date(), sep = ''),
                   output_format = 'all',
                   params = list(
                    data_dir = yaml$data_dir,
                    soup_fraction_value_default = yaml$soup_fraction_value_default,
                    root_dir = yaml$root_dir,
                    metadata_dir = yaml$metadata_dir,
                    metadata_file = yaml$metadata_file,
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

###############################################################################################################
# (2) Seurat QC metrics
# Run the seurat_qc script for each sample/library and save html/pdf reports per each
source(paste0(analysis_dir, "/", "02B_run_seurat_qc_multiple_samples.R"))

###############################################################################################################
# (3) Estimating and filtering out doublets
rmarkdown::render('03_run_scDblFinder.Rmd', 
                  clean = TRUE,
                  output_dir = file.path(scDblFinder_dir),
                  output_file = paste('Report-', 'scDblFinder', '-', Sys.Date(), sep = ''),
                  output_format = 'all',
                  params = list(
                    root_dir = yaml$root_dir,
                    metadata_dir = yaml$metadata_dir,
                    metadata_file = yaml$metadata_file,
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

##############################################################################################################
# (4) Merging filtered data
rmarkdown::render('04_run_filter_object.Rmd', 
                  clean = TRUE,
                  output_dir = file.path(Filter_object_dir),
                  output_file = paste('Report-', 'Filter-object', '-', Sys.Date(), sep = ''),
                  output_format = 'all',
                  params = list(
                    num_dim = yaml$num_dim_filter_object,
                    num_neighbors = yaml$num_neighbors_filter_object,
                    use_SoupX_filtering = yaml$use_SoupX_filtering_filter_object,
                    use_condition_split = yaml$use_condition_split_filter_object,
                    print_pdf = yaml$print_pdf_filter_object,
                    use_scDblFinder_filtering = yaml$use_scDblFinder_filtering_filter_object,
                    grouping = yaml$grouping,
                    genome_name = yaml$genome_name_upstream,
                    Regress_Cell_Cycle_value = yaml$Regress_Cell_Cycle_value,
                    assay = yaml$assay_filter_object,
                    normalize_method = yaml$normalize_method,
                    num_pcs = yaml$num_pcs,
                    nfeatures_value = yaml$nfeatures_value,
                    prefix = yaml$prefix,
                    condition_value1 = yaml$condition_value1,
                    condition_value2 = yaml$condition_value2,
                    condition_value3 = yaml$condition_value3,
                    PCA_Feature_List_value = yaml$PCA_Feature_List_value,
                    root_dir = yaml$root_dir,
                    metadata_dir = yaml$metadata_dir,
                    metadata_file = yaml$metadata_file,
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

################################################################################################################
# (5) Final QC summary report
rmarkdown::render('05_run_summary_report.Rmd', 
                  clean = TRUE,
                  output_dir = file.path(Final_summary_report_dir),
                  output_file = paste('Report-', 'Final-summary', '-', Sys.Date(), sep = ''),
                  output_format = 'all',
                  params = list(
                    use_SoupX_filtering = yaml$use_SoupX_filtering_summary_report,
                    use_scDblFinder_filtering = yaml$use_scDblFinder_filtering_summary_report,
                    cellranger_parameters = yaml$cellranger_parameters,
                    root_dir = yaml$root_dir,
                    metadata_dir = yaml$metadata_dir,
                    metadata_file = yaml$metadata_file,
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

################################################################################################################   
