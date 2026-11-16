# Build a staged DayCent run plan from scenario_matrix.csv.
#
# The plan preserves the calibrated eq -> base -> cnt structure for default
# runs, then branches alternative 2008-2019 cnt-period histories before the
# 2020-2050 experimental period. It is safe to regenerate whenever
# scenario_matrix.csv changes.

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

rel_path <- function(path, root) {
  normalized_path <- normalizePath(path, winslash = "/", mustWork = FALSE)
  normalized_root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  sub(paste0("^", normalized_root, "/?"), "", normalized_path)
}

path_exists <- function(path, repo_root) {
  file.exists(file.path(repo_root, path))
}

first_token <- function(x) {
  parts <- strsplit(trimws(x), "\\s+")[[1]]
  if (length(parts) == 0) {
    return(NA_character_)
  }
  parts[1]
}

schedule_site_file <- function(schedule_file, repo_root) {
  schedule_path <- file.path(repo_root, schedule_file)
  if (!file.exists(schedule_path)) {
    return(NA_character_)
  }

  lines <- readLines(schedule_path, n = 3, warn = FALSE)
  if (length(lines) < 3) {
    return(NA_character_)
  }

  first_token(lines[3])
}

read_schedule_registry <- function(repo_root) {
  registry_path <- file.path(repo_root, "analysis", "schedule_registry.csv")
  if (!file.exists(registry_path)) {
    return(data.frame())
  }

  registry <- read.csv(
    registry_path,
    stringsAsFactors = FALSE,
    check.names = FALSE,
    na.strings = c("", "NA")
  )
  registry$active <- truthy(registry$active)
  registry[registry$active, , drop = FALSE]
}

apply_schedule_registry <- function(plan, registry) {
  plan$source_schedule_file <- NA_character_
  plan$schedule_description <- NA_character_
  plan$schedule_origin <- NA_character_
  plan$schedule_notes <- NA_character_
  plan$schedule_registry_match <- FALSE

  if (nrow(registry) == 0) {
    return(plan)
  }

  for (i in seq_len(nrow(registry))) {
    row <- registry[i, ]
    match_index <-
      plan$stage_name == row$stage_name &
      plan$run_name == row$run_name

    if (!is.na(row$scenario_id) && nzchar(row$scenario_id)) {
      match_index <- match_index & plan$scenario_id == row$scenario_id
    }

    if (!any(match_index)) {
      next
    }

    if (!is.na(row$schedule_file) && nzchar(row$schedule_file)) {
      plan$schedule_file[match_index] <- row$schedule_file
      plan$schedule_stem[match_index] <-
        sub("\\.sch$", "", basename(row$schedule_file))
    }

    plan$source_schedule_file[match_index] <- row$source_schedule_file
    plan$schedule_description[match_index] <- row$schedule_description
    plan$schedule_origin[match_index] <- row$schedule_origin
    plan$schedule_notes[match_index] <- row$schedule_notes
    plan$schedule_registry_match[match_index] <- TRUE
  }

  plan
}

make_row <- function(
  plan_id,
  scenario_id,
  site_id,
  stage_order,
  stage_name,
  run_scope,
  run_name,
  schedule_file,
  previous_run_name,
  period,
  outfiles_file,
  output_dir,
  notes = "",
  fix_overrides = ""
) {
  data.frame(
    plan_id = plan_id,
    scenario_id = scenario_id,
    site_id = site_id,
    stage_order = stage_order,
    stage_name = stage_name,
    run_scope = run_scope,
    run_name = run_name,
    schedule_stem = sub("\\.sch$", "", basename(schedule_file)),
    schedule_file = schedule_file,
    previous_run_name = previous_run_name,
    period = period,
    outfiles_file = outfiles_file,
    output_dir = output_dir,
    notes = notes,
    fix_overrides = fix_overrides,
    stringsAsFactors = FALSE
  )
}

shared_eq_run <- function(site_id, weather_sequence) {
  if (site_id == "enfarm" && weather_sequence == "w_obs") {
    return(list(
      run_name = "eq",
      schedule_file = "sites/enfarm/enfarm_eq.sch",
      previous_run_name = "",
      period = "eq",
      outfiles_file = "sites/enfarm/outfiles_eq.in",
      output_dir = "sites/enfarm/outputs/eq",
      notes = "Existing observed-weather equilibrium spinup"
    ))
  }

  run_name <- paste("eq", weather_sequence, sep = "_")
  list(
    run_name = run_name,
    schedule_file = file.path("sites", site_id, paste0(site_id, "_", run_name, ".sch")),
    previous_run_name = "",
    period = "eq",
    outfiles_file = file.path("sites", site_id, "outfiles_eq.in"),
    output_dir = file.path("sites", site_id, "outputs", run_name),
    notes = "Generated equilibrium spinup placeholder"
  )
}

base_run <- function(site_id, weather_sequence, eq_run_name) {
  if (site_id == "enfarm" && weather_sequence == "w_obs") {
    return(list(
      run_name = "base",
      schedule_file = "sites/enfarm/enfarm_base.sch",
      previous_run_name = eq_run_name,
      period = "base",
      outfiles_file = "sites/enfarm/outfiles_base.in",
      output_dir = "sites/enfarm/outputs/base",
      notes = "Existing calibrated historic land-use run, 1848-2007"
    ))
  }

  run_name <- paste("base", weather_sequence, sep = "_")
  list(
    run_name = run_name,
    schedule_file = file.path("sites", site_id, paste0(site_id, "_", run_name, ".sch")),
    previous_run_name = eq_run_name,
    period = "base",
    outfiles_file = file.path("sites", site_id, "outfiles_base.in"),
    output_dir = file.path("sites", site_id, "outputs", run_name),
    notes = "Generated base-period placeholder"
  )
}

cnt_run <- function(site_id, historic_land_use, weather_sequence, base_run_name) {
  if (
    site_id == "enfarm" &&
      historic_land_use == "hlu_site" &&
      weather_sequence == "w_obs"
  ) {
    return(list(
      run_name = "cnt",
      schedule_file = "sites/enfarm/enfarm_cnt.sch",
      previous_run_name = base_run_name,
      period = "cnt",
      outfiles_file = "sites/enfarm/outfiles_cnt.in",
      output_dir = "sites/enfarm/outputs/cnt",
      notes = "Existing calibrated contemporary historical land-use run, 2008-2019"
    ))
  }

  run_name <- paste("cnt", historic_land_use, weather_sequence, sep = "_")
  list(
    run_name = run_name,
    schedule_file = file.path("sites", site_id, paste0(site_id, "_", run_name, ".sch")),
    previous_run_name = base_run_name,
    period = "cnt",
    outfiles_file = file.path("sites", site_id, "outfiles_cnt.in"),
    output_dir = file.path("sites", site_id, "outputs", run_name),
    notes = "Alternative contemporary historical land-use run, 2008-2019"
  )
}

exp_run <- function(scenario_row, previous_run_name) {
  scenario_id <- scenario_row[["scenario_id"]]
  site_id <- scenario_row[["site_id"]]
  list(
    run_name = scenario_id,
    schedule_file = scenario_row[["schedule_file"]],
    previous_run_name = previous_run_name,
    period = "exp",
    outfiles_file = file.path("sites", site_id, "outfiles_analysis.in"),
    output_dir = scenario_row[["output_dir"]],
    notes = "Scenario-specific experimental run, 2020-2050",
    # fix.100 values set for this run only (e.g. DEC4=0.00220); spinup and
    # history stages always use the library values
    fix_overrides = if ("fix_overrides" %in% names(scenario_row) && !is.na(scenario_row[["fix_overrides"]])) {
      as.character(scenario_row[["fix_overrides"]])
    } else {
      ""
    }
  )
}

add_readiness <- function(plan, repo_root) {
  plan$schedule_exists <- vapply(plan$schedule_file, path_exists, logical(1), repo_root)
  plan$outfiles_exists <- vapply(plan$outfiles_file, path_exists, logical(1), repo_root)

  plan$schedule_site_file <- vapply(
    plan$schedule_file,
    schedule_site_file,
    character(1),
    repo_root
  )
  plan$schedule_site_file_exists <- ifelse(
    is.na(plan$schedule_site_file),
    FALSE,
    file.exists(file.path(repo_root, "sites", plan$site_id, plan$schedule_site_file))
  )

  previous_bin_paths <- ifelse(
    nzchar(plan$previous_run_name),
    file.path("sites", plan$site_id, paste0(plan$previous_run_name, ".bin")),
    NA_character_
  )
  plan$previous_bin_exists <- ifelse(
    is.na(previous_bin_paths),
    TRUE,
    vapply(previous_bin_paths, path_exists, logical(1), repo_root)
  )

  bin_paths <- file.path("sites", plan$site_id, paste0(plan$run_name, ".bin"))
  plan$bin_exists <- vapply(bin_paths, path_exists, logical(1), repo_root)
  plan$output_dir_exists <- vapply(plan$output_dir, path_exists, logical(1), repo_root)

  plan$ready_to_run <-
    plan$schedule_exists &
    plan$schedule_site_file_exists &
    plan$outfiles_exists &
    plan$previous_bin_exists

  plan$blocked_reason <- ""
  plan$blocked_reason[!plan$schedule_exists] <- "missing schedule"
  plan$blocked_reason[
    plan$schedule_exists &
      !plan$schedule_site_file_exists
  ] <- paste0("missing schedule site file: ", plan$schedule_site_file[
    plan$schedule_exists &
      !plan$schedule_site_file_exists
  ])
  plan$blocked_reason[
    plan$schedule_exists &
      plan$schedule_site_file_exists &
      !plan$outfiles_exists
  ] <- "missing outfiles template"
  plan$blocked_reason[
    plan$schedule_exists &
      plan$schedule_site_file_exists &
      plan$outfiles_exists &
      !plan$previous_bin_exists
  ] <- "missing previous bin"

  plan
}

script_dir <- get_script_dir()
repo_root <- normalizePath(file.path(script_dir, ".."), mustWork = TRUE)
scenario_matrix_path <- file.path(repo_root, "analysis", "scenario_matrix.csv")
output_path <- file.path(repo_root, "analysis", "daycent_run_plan.csv")

scenario_matrix <- read.csv(
  scenario_matrix_path,
  stringsAsFactors = FALSE,
  check.names = FALSE
)

rows <- list()

base_key_cols <- c("site_id", "weather_sequence")
base_keys <- unique(scenario_matrix[, base_key_cols, drop = FALSE])

for (i in seq_len(nrow(base_keys))) {
  setup <- base_keys[i, ]
  site_id <- setup$site_id
  weather_sequence <- setup$weather_sequence

  eq <- shared_eq_run(site_id, weather_sequence)
  base <- base_run(site_id, weather_sequence, eq$run_name)

  rows[[length(rows) + 1]] <- make_row(
    plan_id = paste("setup", site_id, weather_sequence, "eq", sep = "_"),
    scenario_id = "",
    site_id = site_id,
    stage_order = 1,
    stage_name = "equilibrium",
    run_scope = "shared",
    run_name = eq$run_name,
    schedule_file = eq$schedule_file,
    previous_run_name = eq$previous_run_name,
    period = eq$period,
    outfiles_file = eq$outfiles_file,
    output_dir = eq$output_dir,
    notes = eq$notes
  )

  rows[[length(rows) + 1]] <- make_row(
    plan_id = paste("setup", site_id, weather_sequence, "base", sep = "_"),
    scenario_id = "",
    site_id = site_id,
    stage_order = 2,
    stage_name = "base",
    run_scope = "shared",
    run_name = base$run_name,
    schedule_file = base$schedule_file,
    previous_run_name = base$previous_run_name,
    period = base$period,
    outfiles_file = base$outfiles_file,
    output_dir = base$output_dir,
    notes = base$notes
  )
}

cnt_key_cols <- c("site_id", "historic_land_use", "weather_sequence")
cnt_keys <- unique(scenario_matrix[, cnt_key_cols, drop = FALSE])

for (i in seq_len(nrow(cnt_keys))) {
  setup <- cnt_keys[i, ]
  site_id <- setup$site_id
  historic_land_use <- setup$historic_land_use
  weather_sequence <- setup$weather_sequence

  eq <- shared_eq_run(site_id, weather_sequence)
  base <- base_run(site_id, weather_sequence, eq$run_name)
  cnt <- cnt_run(site_id, historic_land_use, weather_sequence, base$run_name)

  rows[[length(rows) + 1]] <- make_row(
    plan_id = paste("setup", site_id, historic_land_use, weather_sequence, "cnt", sep = "_"),
    scenario_id = "",
    site_id = site_id,
    stage_order = 3,
    stage_name = "cnt",
    run_scope = "shared",
    run_name = cnt$run_name,
    schedule_file = cnt$schedule_file,
    previous_run_name = cnt$previous_run_name,
    period = cnt$period,
    outfiles_file = cnt$outfiles_file,
    output_dir = cnt$output_dir,
    notes = cnt$notes
  )
}

for (i in seq_len(nrow(scenario_matrix))) {
  scenario <- scenario_matrix[i, ]
  eq <- shared_eq_run(scenario$site_id, scenario$weather_sequence)
  base <- base_run(scenario$site_id, scenario$weather_sequence, eq$run_name)
  cnt <- cnt_run(
    scenario$site_id,
    scenario$historic_land_use,
    scenario$weather_sequence,
    base$run_name
  )
  exp <- exp_run(scenario, cnt$run_name)

  rows[[length(rows) + 1]] <- make_row(
    plan_id = paste("scenario", scenario$scenario_id, "exp", sep = "_"),
    scenario_id = scenario$scenario_id,
    site_id = scenario$site_id,
    stage_order = 4,
    stage_name = "exp",
    run_scope = "scenario",
    run_name = exp$run_name,
    schedule_file = exp$schedule_file,
    previous_run_name = exp$previous_run_name,
    period = exp$period,
    outfiles_file = exp$outfiles_file,
    output_dir = exp$output_dir,
    notes = exp$notes,
    fix_overrides = exp$fix_overrides
  )
}

plan <- do.call(rbind, rows)
plan <- plan[!duplicated(plan[, c("stage_name", "run_name")]), ]
plan <- plan[order(plan$stage_order, plan$site_id, plan$run_name), ]
row.names(plan) <- NULL

schedule_registry <- read_schedule_registry(repo_root)
plan <- apply_schedule_registry(plan, schedule_registry)
plan <- add_readiness(plan, repo_root)

write.csv(plan, output_path, row.names = FALSE)

message("Wrote ", nrow(plan), " planned DayCent run rows to ", output_path)
message("Ready to run now: ", sum(truthy(plan$ready_to_run)))
message("Already have bin files: ", sum(truthy(plan$bin_exists)))
