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
analysis_dir <- file.path(root_dir, "analyses", "integrative-analysis") 
report_dir <- file.path(analysis_dir, "plots") 

################################################################################################################
# Run Rmd scripts to process data per method
################################################################################################################
integration_method=yaml$integration_method
future_globals_value <- as.numeric(yaml$future_globals_value_integrative) * 1024^3

rmarkdown::render('01-integrative-analysis.Rmd', clean = TRUE,
                  output_dir = file.path(report_dir),
                  output_file = c(paste('Report-', glue::glue('integrative-analysis-{integration_method}'), '-', Sys.Date(), sep = '')),
                  output_format = 'all',
                  params = list(
                    # the following parameters are defined in the `yaml` file
                    use_seurat_integration = yaml$use_seurat_integration,
                    use_harmony_integration = yaml$use_harmony_integration,
                    use_liger_integration = yaml$use_liger_integration,
                    integration_method = yaml$integration_method,
                    num_dim_seurat =yaml$num_dim_seurat,
                    num_dim_seurat_integration = yaml$num_dim_seurat_integration,
                    big_data_value = yaml$big_data_value, 
                    num_dim_harmony = yaml$num_dim_harmony,
                    n_neighbors_value = yaml$n_neighbors_value,
                    variable_value = yaml$variable_value,
                    reference_list_value = yaml$reference_list_value, 
                    PCA_Feature_List_value = yaml$PCA_Feature_List_value,       
                    genome_name = yaml$genome_name_upstream,
                    nfeatures_value = yaml$nfeatures_value,
                    Regress_Cell_Cycle_value = yaml$Regress_Cell_Cycle_value,
                    assay = yaml$assay_filter_object,
                    root_dir = yaml$root_dir,
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