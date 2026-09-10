#' Resolve and read the snap project YAML config.
#'
#' WDL / Sprocket tasks set \code{SNAP_CONFIG_FILE} (see wdl/tasks.wdl) to
#' \code{inputs/project_parameters.generated.yaml}. Interactive runs, LSF jobs,
#' and launch_full_pipeline.sh do not set that variable and use the master
#' \code{project_parameters.Config.yaml} instead.
#'
#' @param snap_root Project root (parent of \code{analyses/} and \code{inputs/}).
#' @return Parsed YAML as a list; path used is in attribute \code{snap_config_path}.
#' @export
snap_is_wdl_run <- function() {
  nzchar(Sys.getenv("SNAP_CONFIG_FILE", unset = ""))
}

snap_read_master_config <- function(snap_root = NULL) {
  if (!requireNamespace("yaml", quietly = TRUE)) {
    stop("Install yaml: install.packages('yaml')")
  }

  snap_root <- snap_resolve_root(snap_root)
  config_path <- file.path(snap_root, "project_parameters.Config.yaml")

  if (!file.exists(config_path)) {
    stop("Config not found: ", config_path)
  }

  config_path <- normalizePath(config_path, winslash = "/", mustWork = TRUE)
  cfg <- yaml::read_yaml(config_path)
  attr(cfg, "snap_config_path") <- config_path
  cfg
}

snap_read_config <- function(snap_root = NULL) {
  if (!requireNamespace("yaml", quietly = TRUE)) {
    stop("Install yaml: install.packages('yaml')")
  }

  snap_root <- snap_resolve_root(snap_root)

  if (snap_is_wdl_run()) {
    env_path <- Sys.getenv("SNAP_CONFIG_FILE", unset = "")
    if (!file.exists(env_path)) {
      stop("SNAP_CONFIG_FILE is set but not found: ", env_path)
    }
    config_path <- normalizePath(env_path, winslash = "/", mustWork = TRUE)
  } else {
    return(snap_read_master_config(snap_root))
  }

  cfg <- yaml::read_yaml(config_path)
  attr(cfg, "snap_config_path") <- config_path
  cfg
}

#' Load project YAML for the current run mode (WDL vs interactive/LSF).
#'
#' Call from module entry scripts under \code{analyses/<module>/}.
snap_load_project_config <- function(snap_root = NULL) {
  snap_root <- snap_resolve_root(snap_root)
  cfg <- if (snap_is_wdl_run()) {
    snap_read_config(snap_root)
  } else {
    snap_read_master_config(snap_root)
  }
  message("Using config: ", attr(cfg, "snap_config_path"))
  cfg
}

snap_config_path <- function(snap_root = NULL) {
  attr(snap_read_config(snap_root = snap_root), "snap_config_path")
}

snap_resolve_root <- function(snap_root = NULL) {
  if (is.null(snap_root)) {
    normalizePath(file.path(getwd(), "..", ".."), winslash = "/", mustWork = FALSE)
  } else {
    normalizePath(snap_root, winslash = "/", mustWork = TRUE)
  }
}
