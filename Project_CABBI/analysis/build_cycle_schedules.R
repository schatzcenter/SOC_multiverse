# Build versioned cycling schedules from the established Enfarm practice templates.

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
source_dir <- file.path(repo_root, "sites", "enfarm", "v1schedules")
output_dir <- file.path(repo_root, "sites", "enfarm", "v2schedules")
frequencies <- c(2L, 3L, 4L, 5L, 6L, 7L, 8L, 10L)
source_files <- c(
  NT = "cnt2_corn_notill_cycle.sch",
  RT = "cnt2_corn_reducetill_cycle.sch",
  CC = "cnt2_corn_CC_cycle.sch"
)

if (!dir.exists(output_dir)) {
  stop("Missing output directory: ", output_dir, call. = FALSE)
}

created_count <- 0L
existing_count <- 0L

renumber_events <- function(lines, year) {
  vapply(lines, function(line) {
    leading_space <- sub("^([[:space:]]*).*$", "\\1", line)
    after_year <- sub("^[[:space:]]*[0-9]+", "", line)
    paste0(leading_space, year, after_year)
  }, character(1), USE.NAMES = FALSE)
}

for (practice in names(source_files)) {
  source_path <- file.path(source_dir, source_files[[practice]])
  if (!file.exists(source_path)) {
    stop("Missing source schedule: ", source_path, call. = FALSE)
  }

  lines <- readLines(source_path, warn = FALSE)
  option_line <- grep("^Year Month Option$", trimws(lines))[1]
  sentinel_line <- grep("^-999 -999 X$", trimws(lines))[1]
  if (is.na(option_line) || is.na(sentinel_line) || sentinel_line <= option_line) {
    stop("Could not locate the management event section in ", source_path, call. = FALSE)
  }

  event_section <- seq.int(option_line + 1L, sentinel_line - 1L)
  is_event <- grepl(
    "^[[:space:]]*[0-9]+[[:space:]]+[0-9]+[[:space:]]+[A-Z][A-Z0-9]*([[:space:]]|$)",
    lines[event_section]
  )
  event_lines <- lines[event_section][is_event]
  event_years <- as.integer(sub("^[[:space:]]*([0-9]+).*", "\\1", event_lines))
  conservation_template <- event_lines[event_years == 1L]
  conventional_template <- event_lines[event_years == 5L]

  if (length(conservation_template) == 0 || length(conventional_template) == 0) {
    stop("Expected conservation year 1 and conventional year 5 events in ", source_path, call. = FALSE)
  }

  # The cover crop planted in the last conservation year must be terminated in
  # the conventional year the same way as in the conservation years: herbicide
  # and LAST on day 117, pre-plant cultivation (D491) moved to day 118.
  if (practice == "CC") {
    termination_events <- grep("[[:space:]]117[[:space:]]+(CULT[[:space:]]+HC|LAST)([[:space:]]|$)",
                               conservation_template, value = TRUE)
    if (length(termination_events) != 2) {
      stop("Expected CULT HC and LAST termination events on day 117 in ", source_path, call. = FALSE)
    }
    d491 <- grep("[[:space:]]128[[:space:]]+CULT[[:space:]]+D491", conventional_template)
    if (length(d491) != 1) {
      stop("Expected one day-128 CULT D491 in the conventional year of ", source_path, call. = FALSE)
    }
    conventional_template[d491] <- sub("([[:space:]])128([[:space:]]+CULT)", "\\1118\\2", conventional_template[d491])
    conventional_template <- c(termination_events, conventional_template)
  }

  for (year in 2:4) {
    comparison <- event_lines[event_years == year]
    normalized <- sub("^[[:space:]]*[0-9]+", "", comparison)
    template_normalized <- sub("^[[:space:]]*[0-9]+", "", conservation_template)
    if (!identical(normalized, template_normalized)) {
      stop("Conservation event pattern differs across years 1-4 in ", source_path, call. = FALSE)
    }
  }

  prefix <- lines[seq_len(min(which(is_event)) + event_section[1] - 2L)]
  repeat_line <- grep("Repeats # years", prefix, fixed = TRUE)
  site_line <- grep("Site file name", prefix, fixed = TRUE)
  if (length(repeat_line) != 1 || length(site_line) != 1) {
    stop("Expected one repeat-count line and one site-file line in ", source_path, call. = FALSE)
  }

  for (frequency in frequencies) {
    target_name <- paste0("exp_corn_", practice, "_cycle_", frequency, ".sch")
    target_path <- file.path(output_dir, target_name)
    if (file.exists(target_path)) {
      existing_count <- existing_count + 1L
      next
    }

    schedule_prefix <- prefix
    schedule_prefix[repeat_line] <- sub("^[[:space:]]*[0-9]+", as.character(frequency), schedule_prefix[repeat_line])
    schedule_prefix[site_line] <- sub("^[[:space:]]*[^[:space:]]+", "enfarm_cnt.100", schedule_prefix[site_line])

    conservation_years <- seq_len(frequency - 1L)
    repeated_conservation <- unlist(lapply(conservation_years, function(year) {
      renumber_events(conservation_template, year)
    }), use.names = FALSE)
    final_conventional <- renumber_events(conventional_template, frequency)
    generated_lines <- c(schedule_prefix, repeated_conservation, final_conventional, lines[sentinel_line:length(lines)])

    writeLines(generated_lines, target_path, useBytes = TRUE)
    created_count <- created_count + 1L
  }
}

message("Wrote ", created_count, " schedules; preserved ", existing_count, " existing schedules in ", output_dir)
