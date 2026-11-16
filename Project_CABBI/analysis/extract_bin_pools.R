# Extract annual carbon pools and N volatilization accumulators from exp-stage
# DayCent binaries with list100.
#
# The CSV outputs do not include somtc, totc, totsysc, or the volatilization
# accumulators, but every .bin stores them. This script runs list100 on each
# exp-stage bin, keeps one start-of-year snapshot per year, and writes
# <output_dir>/<run_name>_binpools.csv. A run is re-extracted whenever its .bin
# is newer than its existing binpools file.

get_script_dir <- function() {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(file_arg) > 0) {
    return(dirname(normalizePath(sub("^--file=", "", file_arg[1]))))
  }
  if (!is.null(sys.frames()[[1]]$ofile)) {
    return(dirname(normalizePath(sys.frames()[[1]]$ofile)))
  }
  getwd()
}

script_dir <- get_script_dir()
repo_root <- normalizePath(file.path(script_dir, ".."), mustWork = TRUE)
list100_exe <- file.path(repo_root, "executables", "list100_DayCent_CABBI.exe")
plan_path <- file.path(repo_root, "analysis", "daycent_run_plan.csv")
binpool_vars <- c("somsc", "somtc", "totc", "totsysc", "volgma", "volexa", "volpla")
vars_file_name <- "outvars_binpools.txt"

if (!file.exists(list100_exe)) {
  stop("Missing list100 executable: ", list100_exe, call. = FALSE)
}

# Parse a list100 .lis file and keep the last row at each start-of-year time.
# At 2020.00 the last row is the exp-run start, where accumulators are reset.
read_lis_annual <- function(lis_path) {
  header <- strsplit(trimws(readLines(lis_path, n = 1)), "[[:space:]]+")[[1]]
  lis <- read.table(lis_path, skip = 2, header = FALSE, col.names = header)
  names(lis) <- header
  lis <- lis[abs(lis$time - round(lis$time)) < 1e-6, , drop = FALSE]
  lis$year <- as.integer(round(lis$time))
  lis <- lis[!duplicated(lis$year, fromLast = TRUE), , drop = FALSE]
  lis[, c("year", binpool_vars)]
}

extract_run <- function(row) {
  site_dir <- file.path(repo_root, "sites", row$site_id)
  output_dir <- file.path(repo_root, row$output_dir)
  bin_path <- file.path(site_dir, paste0(row$run_name, ".bin"))
  out_path <- file.path(output_dir, paste0(row$run_name, "_binpools.csv"))
  if (!file.exists(bin_path)) {
    return("missing_bin")
  }
  if (file.exists(out_path) && file.mtime(out_path) >= file.mtime(bin_path)) {
    return("up_to_date")
  }

  lis_stem <- paste0(row$run_name, "_binpools")
  lis_path <- file.path(site_dir, paste0(lis_stem, ".lis"))
  writeLines(binpool_vars, file.path(site_dir, vars_file_name))
  unlink(lis_path)  # list100 will not overwrite an existing .lis file

  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(site_dir)
  exit_status <- system2(
    list100_exe,
    args = c(row$run_name, lis_stem, vars_file_name),
    stdout = FALSE,
    stderr = FALSE
  )
  if (!isTRUE(exit_status == 0) || !file.exists(lis_path)) {
    return(paste0("failed_", exit_status))
  }

  annual <- read_lis_annual(lis_path)
  unlink(lis_path)
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }
  write.csv(annual, out_path, row.names = FALSE)
  "extracted"
}

plan <- read.csv(plan_path, stringsAsFactors = FALSE, check.names = FALSE)
exp_rows <- plan[plan$stage_name == "exp", , drop = FALSE]

statuses <- character(nrow(exp_rows))
for (i in seq_len(nrow(exp_rows))) {
  statuses[i] <- extract_run(exp_rows[i, ])
}

print(table(statuses))
failed <- exp_rows$run_name[grepl("^failed", statuses)]
if (length(failed) > 0) {
  stop("list100 failed for: ", paste(failed, collapse = ", "), call. = FALSE)
}
