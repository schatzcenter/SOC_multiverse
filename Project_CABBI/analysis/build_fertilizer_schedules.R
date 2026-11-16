# Build fertilizer variants for Enfarm practice, cycle, and reversion templates.
#
# Legacy variants (UAN3/6/8/11/18, no fertilizer) of every earlier template are
# verified; they belong to the set-aside scenarios. Sensitivity-set variants
# (UAN10, UAN30) are built for the templates in the current design: the three
# conventional definitions and NT/RT/CC continuous, and NT/RT/CC 5- and 10-year
# cycles. Run build_conventional_alternatives.R first. Scenarios are defined
# in scenario_levels.csv and set_aside_scenarios.csv (build_scenario_metadata.R).

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
schedule_dir <- file.path(repo_root, "sites", "enfarm", "v2schedules")
if (!dir.exists(schedule_dir)) {
  stop("Missing schedule directory: ", schedule_dir, call. = FALSE)
}

make_templates <- function(continuous_practices, cycle_frequencies, adoption_durations) {
  templates <- data.frame(
    practice = continuous_practices,
    management = "cont",
    source_file = paste0("exp_corn_", continuous_practices, "_cont.sch"),
    stringsAsFactors = FALSE
  )
  for (practice in c("NT", "RT", "CC")) {
    if (length(cycle_frequencies) > 0) {
      templates <- rbind(templates, data.frame(
        practice = practice,
        management = paste0("rev", cycle_frequencies),
        source_file = paste0("exp_corn_", practice, "_cycle_", cycle_frequencies, ".sch"),
        stringsAsFactors = FALSE
      ))
    }
    if (length(adoption_durations) > 0) {
      templates <- rbind(templates, data.frame(
        practice = practice,
        management = paste0("adopt", adoption_durations, "_rev"),
        source_file = paste0("exp_corn_", practice, "_revert_", adoption_durations, ".sch"),
        stringsAsFactors = FALSE
      ))
    }
  }
  templates
}

# Legacy variants (set-aside scenarios): verified against existing files.
legacy_jobs <- merge(
  make_templates(c("CONV", "NT", "RT", "CC"), c(2L, 3L, 4L, 5L, 6L, 7L, 8L, 10L), c(2L, 5L, 10L)),
  data.frame(fertilizer_variant = c("UAN3", "UAN6", "UAN8", "UAN11", "UAN18", "no_fert"))
)
# Sensitivity-set variants.
current_jobs <- merge(
  make_templates(c("CONV", "CONVPLOW", "CONVRT", "NT", "RT", "CC"), c(5L, 10L), integer()),
  data.frame(fertilizer_variant = c("UAN10", "UAN30"))
)
jobs <- rbind(legacy_jobs, current_jobs)

# Each block's repeat length must match its highest event year; otherwise
# DayCent runs the unlisted years with no management (fallow). Blocks after the
# first must continue the weather file ("C"); "F" restarts it at its first year,
# which misaligns weather with single-block comparison runs.
validate_schedule_blocks <- function(lines, path) {
  block_starts <- grep("^[[:space:]]*[0-9]+[[:space:]]+Block", lines)
  block_ends <- grep("^-999", lines)
  for (start in block_starts[-1]) {
    weather_choice <- sub("^[[:space:]]*([A-Z]).*$", "\\1",
                          grep("Weather choice", lines[start:length(lines)], value = TRUE)[1])
    if (!identical(weather_choice, "C")) {
      stop("Block after the first does not continue weather (\"C\") in ", path, call. = FALSE)
    }
  }
  for (start in block_starts) {
    end <- min(block_ends[block_ends > start])
    block_lines <- lines[start:end]
    repeats <- as.integer(sub("^[[:space:]]*([0-9]+).*$", "\\1",
                              grep("Repeats", block_lines, value = TRUE)[1]))
    event_lines <- grep("^[[:space:]]*[0-9]+[[:space:]]+[0-9]+[[:space:]]+[A-Z]", block_lines, value = TRUE)
    event_years <- as.integer(sub("^[[:space:]]*([0-9]+).*$", "\\1", event_lines))
    if (!identical(repeats, max(event_years))) {
      stop("Block repeats (", repeats, ") do not match highest event year (",
           max(event_years), ") in ", path, call. = FALSE)
    }
  }
  invisible(TRUE)
}

write_or_verify <- function(lines, path) {
  if (file.exists(path)) {
    existing_lines <- readLines(path, warn = FALSE)
    if (!identical(existing_lines, lines)) {
      stop("Existing schedule differs from generated content: ", path, call. = FALSE)
    }
    return(FALSE)
  }

  writeLines(lines, path, useBytes = TRUE)
  TRUE
}

created_count <- 0L
verified_count <- 0L
for (i in seq_len(nrow(jobs))) {
  practice <- jobs$practice[i]
  management <- jobs$management[i]
  fertilizer_variant <- jobs$fertilizer_variant[i]
  source_path <- file.path(schedule_dir, jobs$source_file[i])
  if (!file.exists(source_path)) {
    stop("Missing source schedule: ", source_path, call. = FALSE)
  }

  lines <- readLines(source_path, warn = FALSE)
  validate_schedule_blocks(lines, source_path)
  fertilizer_indices <- grep(
    "^[[:space:]]*[0-9]+[[:space:]]+[0-9]+[[:space:]]+FERT[[:space:]]+[^[:space:]]+",
    lines
  )
  fertilizer_types <- sub(
    "^[[:space:]]*[0-9]+[[:space:]]+[0-9]+[[:space:]]+FERT[[:space:]]+([^[:space:]]+).*$",
    "\\1",
    lines[fertilizer_indices]
  )
  if (length(fertilizer_indices) == 0L || any(fertilizer_types != "UAN20")) {
    stop("Expected only UAN20 fertilizer events in ", source_path, call. = FALSE)
  }

  management_suffix <- management
  if (grepl("^rev[0-9]+$", management)) {
    management_suffix <- paste0("cycle_", sub("^rev", "", management))
  } else if (grepl("^adopt(2|5|10)_rev$", management)) {
    duration <- sub("^adopt([0-9]+)_rev$", "\\1", management)
    management_suffix <- paste0("revert_", duration)
  }

  target_name <- paste0("exp_corn_", practice, "_", management_suffix, "_", fertilizer_variant, ".sch")
  target_path <- file.path(schedule_dir, target_name)
  variant <- lines
  if (fertilizer_variant == "no_fert") {
    variant <- variant[-fertilizer_indices]
  } else {
    for (event_index in fertilizer_indices) {
      variant[event_index] <- sub("UAN20", fertilizer_variant, variant[event_index], fixed = TRUE)
      variant[event_index] <- sub(
        "#202_kg_N_ha",
        paste0("#fertilizer parameter ", fertilizer_variant),
        variant[event_index],
        fixed = TRUE
      )
    }
  }

  if (write_or_verify(variant, target_path)) {
    created_count <- created_count + 1L
  } else {
    verified_count <- verified_count + 1L
  }
}

message("Created ", created_count, " schedules; verified ", verified_count, " existing schedules.")
