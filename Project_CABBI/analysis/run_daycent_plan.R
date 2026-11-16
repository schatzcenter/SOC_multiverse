# Run selected rows from analysis/daycent_run_plan.csv.
#
# Default behavior is dry-run only. Use --execute to run DayCent. Existing .bin
# files are skipped unless --force is supplied.

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

truthy <- function(x) {
  tolower(trimws(as.character(x))) %in% c("true", "t", "1", "yes", "y")
}

parse_args <- function(args) {
  parsed <- list(
    execute = FALSE,
    force = FALSE,
    supplemental_only = FALSE,
    limit = Inf,
    stage = NA_character_,
    scenario = NA_character_,
    run_name = NA_character_,
    run_pattern = NA_character_
  )

  for (arg in args) {
    if (arg == "--execute") {
      parsed$execute <- TRUE
    } else if (arg == "--supplemental-only") {
      parsed$supplemental_only <- TRUE
    } else if (arg == "--force") {
      parsed$force <- TRUE
    } else if (grepl("^--limit=", arg)) {
      parsed$limit <- as.integer(sub("^--limit=", "", arg))
    } else if (grepl("^--stage=", arg)) {
      parsed$stage <- sub("^--stage=", "", arg)
    } else if (grepl("^--scenario=", arg)) {
      parsed$scenario <- sub("^--scenario=", "", arg)
    } else if (grepl("^--run-name=", arg)) {
      parsed$run_name <- sub("^--run-name=", "", arg)
    } else if (grepl("^--run-pattern=", arg)) {
      parsed$run_pattern <- sub("^--run-pattern=", "", arg)
    }
  }

  parsed
}

rel_path <- function(path, root) {
  normalized_path <- normalizePath(path, winslash = "/", mustWork = FALSE)
  normalized_root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  sub(paste0("^", normalized_root, "/?"), "", normalized_path)
}

copy_library_files <- function(lib_dir, site_dir) {
  lib_files <- list.files(lib_dir, pattern = "\\.100$", full.names = TRUE)
  if (length(lib_files) == 0) {
    stop("No .100 library files found in ", lib_dir, call. = FALSE)
  }

  file.copy(lib_files, site_dir, overwrite = TRUE)
}

# Set fix.100 parameters for one run, e.g. "DEC4=0.00220;DEC5(2)=0.2" (from the
# run plan's fix_overrides column). Applied to the site copy after the library
# files are copied, so each run starts from the library values.
apply_fix_overrides <- function(site_dir, overrides) {
  if (is.null(overrides) || is.na(overrides) || !nzchar(trimws(overrides))) {
    return(invisible(character()))
  }
  fix_path <- file.path(site_dir, "fix.100")
  lines <- readLines(fix_path, warn = FALSE)
  pairs <- strsplit(strsplit(overrides, ";", fixed = TRUE)[[1]], "=", fixed = TRUE)
  for (pair in pairs) {
    name <- trimws(pair[1])
    value <- as.numeric(pair[2])
    if (is.na(value)) stop("Invalid fix.100 override: ", paste(pair, collapse = "="), call. = FALSE)
    hit <- grep(paste0("'", gsub("([()])", "\\\\\\1", name), "'"), lines)
    if (length(hit) != 1L) stop("fix.100 parameter not found once: ", name, call. = FALSE)
    lines[hit] <- sprintf("%-18s'%s'", format(value, scientific = FALSE), name)
  }
  writeLines(lines, fix_path)
  invisible(overrides)
}

first_token <- function(x) {
  parts <- strsplit(trimws(x), "\\s+")[[1]]
  if (length(parts) == 0) {
    return(NA_character_)
  }
  parts[1]
}

schedule_site_file <- function(schedule_path) {
  if (!file.exists(schedule_path)) {
    return(NA_character_)
  }

  lines <- readLines(schedule_path, n = 3, warn = FALSE)
  if (length(lines) < 3) {
    return(NA_character_)
  }

  first_token(lines[3])
}

stage_schedule_file <- function(schedule_path, site_dir) {
  staged_path <- file.path(site_dir, basename(schedule_path))
  if (!identical(normalizePath(schedule_path, winslash = "/", mustWork = TRUE),
                 normalizePath(staged_path, winslash = "/", mustWork = FALSE))) {
    file.copy(schedule_path, staged_path, overwrite = TRUE)
  }
  staged_path
}

collect_daycent_outputs <- function(site_dir, output_dir, run_name) {
  generated_files <- list.files(
    site_dir,
    pattern = "\\.(csv|out)$",
    full.names = TRUE
  )

  if (length(generated_files) == 0) {
    return(character())
  }

  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  moved <- character()
  for (path in generated_files) {
    base_name <- basename(path)
    if (!startsWith(base_name, paste0(run_name, "_"))) {
      base_name <- paste0(run_name, "_", base_name)
    }
    dest <- file.path(output_dir, base_name)
    if (file.exists(dest)) {
      unlink(dest)
    }
    ok <- file.rename(path, dest)
    if (!ok) {
      file.copy(path, dest, overwrite = TRUE)
      unlink(path)
    }
    moved <- c(moved, dest)
  }

  moved
}

run_daycent_row <- function(row, repo_root, daycent_exe, lib_dir, force = FALSE) {
  site_dir <- file.path(repo_root, "sites", row$site_id)
  output_dir <- file.path(repo_root, row$output_dir)
  schedule_path <- file.path(repo_root, row$schedule_file)
  outfiles_path <- file.path(repo_root, row$outfiles_file)
  bin_path <- file.path(site_dir, paste0(row$run_name, ".bin"))

  if (!file.exists(schedule_path)) {
    stop("Missing schedule file: ", row$schedule_file, call. = FALSE)
  }
  required_site_file <- schedule_site_file(schedule_path)
  if (is.na(required_site_file)) {
    stop("Could not read site file from schedule: ", row$schedule_file, call. = FALSE)
  }
  if (!file.exists(file.path(site_dir, required_site_file))) {
    stop("Missing schedule site file: ", required_site_file, call. = FALSE)
  }
  if (!file.exists(outfiles_path)) {
    stop("Missing outfiles template: ", row$outfiles_file, call. = FALSE)
  }
  if (nzchar(row$previous_run_name)) {
    prev_bin <- file.path(site_dir, paste0(row$previous_run_name, ".bin"))
    if (!file.exists(prev_bin)) {
      stop("Missing previous bin: ", basename(prev_bin), call. = FALSE)
    }
  }
  if (file.exists(bin_path) && !force) {
    return(list(status = "skipped_existing_bin", moved_files = character()))
  }
  if (file.exists(bin_path) && force) {
    unlink(bin_path)
  }

  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  copy_library_files(lib_dir, site_dir)
  if ("fix_overrides" %in% names(row) && length(apply_fix_overrides(site_dir, row$fix_overrides)) > 0) {
    # restore the library fix.100 in the site folder after this run
    on.exit(file.copy(file.path(lib_dir, "fix.100"), file.path(site_dir, "fix.100"), overwrite = TRUE),
            add = TRUE)
  }
  stage_schedule_file(schedule_path, site_dir)
  file.copy(outfiles_path, file.path(site_dir, "outfiles.in"), overwrite = TRUE)

  args <- c("-s", row$schedule_stem, "-n", row$run_name)
  if (nzchar(row$previous_run_name)) {
    args <- c(args, "-e", row$previous_run_name)
  }

  stdout_log <- file.path(output_dir, paste0(row$run_name, "_stdout_daycent.log"))
  stderr_log <- file.path(output_dir, paste0(row$run_name, "_stderr_daycent.log"))
  if (file.exists(stdout_log)) {
    unlink(stdout_log)
  }
  if (file.exists(stderr_log)) {
    unlink(stderr_log)
  }

  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(site_dir)

  exit_status <- system2(
    command = daycent_exe,
    args = args,
    wait = TRUE,
    stdout = stdout_log,
    stderr = stderr_log
  )

  if (!isTRUE(exit_status == 0)) {
    return(list(status = paste0("failed_", exit_status), moved_files = character()))
  }

  moved_files <- collect_daycent_outputs(site_dir, output_dir, row$run_name)
  list(status = "completed", moved_files = moved_files)
}

script_dir <- get_script_dir()
repo_root <- normalizePath(file.path(script_dir, ".."), mustWork = TRUE)
args <- parse_args(commandArgs(trailingOnly = TRUE))

plan_path <- file.path(repo_root, "analysis", "daycent_run_plan.csv")
plan <- read.csv(plan_path, stringsAsFactors = FALSE, check.names = FALSE)

plan$ready_to_run <- truthy(plan$ready_to_run)
plan$bin_exists <- truthy(plan$bin_exists)

selected <- plan
if (!is.na(args$stage)) {
  selected <- selected[selected$stage_name == args$stage, ]
}
if (!is.na(args$scenario)) {
  selected <- selected[selected$scenario_id == args$scenario, ]
}
if (!is.na(args$run_name)) {
  selected <- selected[selected$run_name == args$run_name, ]
}
if (!is.na(args$run_pattern)) {
  selected <- selected[grepl(args$run_pattern, selected$run_name), ]
}
if (args$supplemental_only) {
  supplemental_path <- file.path(repo_root, "analysis", "supplemental_scenarios.csv")
  if (!file.exists(supplemental_path)) {
    stop("Missing supplemental scenario list: ", supplemental_path, call. = FALSE)
  }
  supplemental <- read.csv(supplemental_path, stringsAsFactors = FALSE, check.names = FALSE)
  id_columns <- c(
    "conservation_practice",
    "n_rate",
    "historic_land_use",
    "cycling_frequency",
    "weather_sequence"
  )
  if (!all(id_columns %in% names(supplemental))) {
    stop("Supplemental scenario list is missing required ID columns.", call. = FALSE)
  }
  supplemental_ids <- do.call(paste, c(supplemental[id_columns], sep = "_"))
  selected <- selected[selected$scenario_id %in% supplemental_ids, ]
}

selected <- selected[selected$ready_to_run, ]
if (!args$force) {
  selected <- selected[!selected$bin_exists, ]
}
selected <- selected[order(selected$stage_order, selected$run_name), ]

if (is.finite(args$limit) && nrow(selected) > args$limit) {
  selected <- selected[seq_len(args$limit), ]
}

message("Selected ready rows: ", nrow(selected))
if (nrow(selected) > 0) {
  print(selected[, c("stage_order", "stage_name", "run_name", "previous_run_name", "schedule_file")])
}

if (!args$execute) {
  message("Dry run only. Re-run with --execute to launch DayCent.")
  quit(save = "no", status = 0)
}

daycent_exe <- file.path(repo_root, "executables", "DayCent_CABBI_test.exe")
lib_dir <- file.path(repo_root, "100libraryfiles")
if (!file.exists(daycent_exe)) {
  stop("Missing DayCent executable: ", daycent_exe, call. = FALSE)
}

run_log <- list()
for (i in seq_len(nrow(selected))) {
  row <- selected[i, ]
  start_time <- Sys.time()
  message("Running ", row$run_name, " (", row$stage_name, ")")

  result <- tryCatch(
    run_daycent_row(
      row = row,
      repo_root = repo_root,
      daycent_exe = daycent_exe,
      lib_dir = lib_dir,
      force = args$force
    ),
    error = function(e) list(status = paste0("error: ", conditionMessage(e)), moved_files = character())
  )

  run_log[[length(run_log) + 1]] <- data.frame(
    run_name = row$run_name,
    scenario_id = row$scenario_id,
    stage_name = row$stage_name,
    status = result$status,
    start_time = as.character(start_time),
    end_time = as.character(Sys.time()),
    moved_file_count = length(result$moved_files),
    stringsAsFactors = FALSE
  )
}

if (length(run_log) > 0) {
  log_path <- file.path(repo_root, "analysis", "daycent_run_log.csv")
  log_df <- do.call(rbind, run_log)
  if (file.exists(log_path)) {
    old_log <- read.csv(log_path, stringsAsFactors = FALSE)
    log_df <- rbind(old_log, log_df)
  }
  write.csv(log_df, log_path, row.names = FALSE)
  message("Wrote run log to ", log_path)
}
