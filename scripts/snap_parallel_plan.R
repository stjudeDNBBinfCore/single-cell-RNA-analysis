#' Configure future plan safely for Singularity + NFS HPC runs.
#'
#' Spawning many multisession workers (or fork-based backends) inside
#' containers on NFS mounts can cause bus errors when R loads packages.
#' Defaults to sequential; override with SNAP_FUTURE_WORKERS (integer >= 1).
snap_set_future_plan <- function(workers = NULL) {
  if (!requireNamespace("future", quietly = TRUE)) {
    return(invisible(NA_integer_))
  }

  if (is.null(workers)) {
    env_val <- Sys.getenv("SNAP_FUTURE_WORKERS", unset = "1")
    workers <- suppressWarnings(as.integer(env_val))
    if (is.na(workers) || workers < 1L) {
      workers <- 1L
    }
  }

  max_cores <- if (requireNamespace("parallelly", quietly = TRUE)) {
    parallelly::availableCores()
  } else {
    1L
  }
  workers <- min(as.integer(workers), max_cores)

  if (workers <= 1L) {
    future::plan(future::sequential)
  } else {
    future::plan(future::multisession, workers = workers)
  }

  invisible(workers)
}
