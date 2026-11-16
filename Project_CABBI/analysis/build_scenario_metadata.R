# Build a flexible scenario matrix from editable factor levels.
#
# Edit analysis/scenario_levels.csv to add, remove, or activate levels. This
# script expands active factorial levels (the sensitivity set) and adds the
# set-aside scenarios in analysis/set_aside_scenarios.csv (earlier levels kept
# for separate analyses, not for the sensitivity/range analyses), then writes
# analysis/scenario_matrix.csv with analysis_set = "sensitivity" or "set_aside".
#
# Conventional practices (conv, convplow, convrt) are counterfactual references
# and run with continuous management only. The default DEC4 level (dec4_def) is
# left out of scenario IDs, so runs made before the DEC4 dimension keep their
# names; other DEC4 levels set fix.100 DEC4 for the 2020-2050 run through the
# fix_overrides column.

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

slug <- function(x) {
  x <- tolower(trimws(as.character(x)))
  x <- gsub("[^a-z0-9]+", "_", x)
  x <- gsub("^_+|_+$", "", x)
  x <- gsub("_+", "_", x)
  x
}

# Levels left out of scenario IDs (default model parameters), so IDs of runs
# made before a dimension was added are unchanged.
id_omitted_levels <- c(dec4 = "dec4_def")

make_scenario_id <- function(df, id_dimensions) {
  parts <- df[, id_dimensions, drop = FALSE]
  for (dimension_name in intersect(names(id_omitted_levels), id_dimensions)) {
    parts[[dimension_name]][parts[[dimension_name]] == id_omitted_levels[[dimension_name]]] <- NA
  }
  apply(parts, 1, function(x) paste(x[!is.na(x)], collapse = "_"))
}

conventional_practices <- c("conv", "convplow", "convrt")
dec4_values <- c(dec4_lo = 0.0022, dec4_def = 0.0025, dec4_hi = 0.0048)

script_dir <- get_script_dir()
repo_root <- normalizePath(file.path(script_dir, ".."), mustWork = TRUE)

levels_path <- file.path(repo_root, "analysis", "scenario_levels.csv")
output_path <- file.path(repo_root, "analysis", "scenario_matrix.csv")

scenario_levels <- read.csv(
  levels_path,
  stringsAsFactors = FALSE,
  na.strings = c("", "NA")
)

scenario_levels$active <- truthy(scenario_levels$active)
scenario_levels$include_in_factorial <- truthy(scenario_levels$include_in_factorial)
scenario_levels$dimension_order <- as.integer(scenario_levels$dimension_order)
scenario_levels$level_order <- as.integer(scenario_levels$level_order)
scenario_levels$dimension <- slug(scenario_levels$dimension)
scenario_levels$level_id <- slug(scenario_levels$level_id)

scenario_levels <- scenario_levels[order(
  scenario_levels$dimension_order,
  scenario_levels$level_order
), ]

factor_levels <- scenario_levels[
  scenario_levels$active & scenario_levels$include_in_factorial,
]

required_dimensions <- c(
  "conservation_practice",
  "n_rate",
  "historic_land_use",
  "cycling_frequency"
)

missing_dimensions <- setdiff(required_dimensions, unique(factor_levels$dimension))
if (length(missing_dimensions) > 0) {
  stop(
    "Missing active factorial levels for: ",
    paste(missing_dimensions, collapse = ", "),
    call. = FALSE
  )
}

factor_dimensions <- unique(factor_levels$dimension)
level_list <- setNames(
  lapply(factor_dimensions, function(dimension_name) {
    factor_levels$level_id[factor_levels$dimension == dimension_name]
  }),
  factor_dimensions
)

scenario_matrix <- expand.grid(level_list, stringsAsFactors = FALSE)

# Conventional (counterfactual) rows do not need cycling or reversion variants.
if (all(c("conservation_practice", "cycling_frequency") %in% names(scenario_matrix))) {
  scenario_matrix <- scenario_matrix[
    !scenario_matrix$conservation_practice %in% conventional_practices |
      scenario_matrix$cycling_frequency == "cont",
  ]
}
scenario_matrix$analysis_set <- "sensitivity"

order_index <- do.call(order, lapply(factor_dimensions, function(dimension_name) {
  match(scenario_matrix[[dimension_name]], level_list[[dimension_name]])
}))
scenario_matrix <- scenario_matrix[order_index, ]
row.names(scenario_matrix) <- NULL

supplemental_path <- file.path(repo_root, "analysis", "set_aside_scenarios.csv")
if (file.exists(supplemental_path)) {
  supplemental_scenarios <- read.csv(
    supplemental_path,
    stringsAsFactors = FALSE,
    check.names = FALSE,
    na.strings = c("", "NA")
  )
  missing_columns <- setdiff(factor_dimensions, names(supplemental_scenarios))
  if (length(missing_columns) > 0) {
    stop(
      "Supplemental scenarios are missing dimensions: ",
      paste(missing_columns, collapse = ", "),
      call. = FALSE
    )
  }

  supplemental_scenarios <- supplemental_scenarios[, factor_dimensions, drop = FALSE]
  for (dimension_name in factor_dimensions) {
    supplemental_scenarios[[dimension_name]] <- slug(supplemental_scenarios[[dimension_name]])
    active_levels <- scenario_levels$level_id[
      scenario_levels$dimension == dimension_name & scenario_levels$active
    ]
    unknown_levels <- setdiff(unique(supplemental_scenarios[[dimension_name]]), active_levels)
    if (length(unknown_levels) > 0) {
      stop(
        "Unknown active levels in supplemental scenarios for ", dimension_name, ": ",
        paste(unknown_levels, collapse = ", "),
        call. = FALSE
      )
    }
  }

  supplemental_ids <- make_scenario_id(supplemental_scenarios, factor_dimensions)
  existing_ids <- make_scenario_id(scenario_matrix, factor_dimensions)
  duplicate_ids <- c(
    supplemental_ids[duplicated(supplemental_ids)],
    intersect(supplemental_ids, existing_ids)
  )
  if (length(duplicate_ids) > 0) {
    stop(
      "Duplicate supplemental scenario IDs: ",
      paste(unique(duplicate_ids), collapse = ", "),
      call. = FALSE
    )
  }

  supplemental_scenarios$analysis_set <- "set_aside"
  scenario_matrix <- rbind(scenario_matrix, supplemental_scenarios)
  message("Added ", nrow(supplemental_scenarios), " set-aside scenarios")
}

scenario_matrix$scenario_id <- make_scenario_id(scenario_matrix, factor_dimensions)
scenario_matrix$site_id <- "enfarm"
scenario_matrix$adoption_year <- 2020L
scenario_matrix$end_year <- 2050L
scenario_matrix$endpoint_years <- "2025;2030;2040;2050"
scenario_matrix$run_status <- "planned"
scenario_matrix$daycent_run_name <- scenario_matrix$scenario_id
scenario_matrix$schedule_file <- file.path(
  "sites",
  "enfarm",
  paste0("enfarm_", scenario_matrix$scenario_id, ".sch")
)
scenario_matrix$output_dir <- file.path(
  "sites",
  "enfarm",
  "outputs",
  scenario_matrix$scenario_id
)

# n_obs uses the unsuffixed base schedules, which apply UAN20 (20.2 g N/m2).
explicit_schedule_rates <- c(
  n_obs = "",
  n_none = "no_fert",
  uan3 = "UAN3",
  uan6 = "UAN6",
  uan8 = "UAN8",
  uan10 = "UAN10",
  uan11 = "UAN11",
  uan18 = "UAN18",
  uan30 = "UAN30"
)
practice_schedule_codes <- c(conv = "CONV", nt = "NT", rt = "RT", cc = "CC",
                             convplow = "CONVPLOW", convrt = "CONVRT")
explicit_schedule_rows <- which(scenario_matrix$n_rate %in% names(explicit_schedule_rates))
for (i in explicit_schedule_rows) {
  practice <- scenario_matrix$conservation_practice[i]
  rate_suffix <- unname(explicit_schedule_rates[scenario_matrix$n_rate[i]])
  cycling_frequency <- scenario_matrix$cycling_frequency[i]

  if (practice %in% conventional_practices) {
    if (cycling_frequency != "cont") {
      stop("Conventional scenarios must use cont management.", call. = FALSE)
    }
    management_suffix <- "cont"
  } else if (cycling_frequency == "cont") {
    management_suffix <- "cont"
  } else if (grepl("^rev[0-9]+$", cycling_frequency)) {
    frequency <- sub("^rev", "", cycling_frequency)
    management_suffix <- paste0("cycle_", frequency)
  } else if (grepl("^adopt(2|5|10)_rev$", cycling_frequency)) {
    duration <- sub("^adopt([0-9]+)_rev$", "\\1", cycling_frequency)
    management_suffix <- paste0("revert_", duration)
  } else {
    stop("No schedule mapping for cycling frequency: ", cycling_frequency, call. = FALSE)
  }

  scenario_matrix$schedule_file[i] <- file.path(
    "sites",
    "enfarm",
    "v2schedules",
    paste0(
      "exp_corn_",
      unname(practice_schedule_codes[practice]),
      "_",
      management_suffix,
      if (nzchar(rate_suffix)) paste0("_", rate_suffix) else "",
      ".sch"
    )
  )
}

for (dimension_name in factor_dimensions) {
  lookup <- scenario_levels[
    scenario_levels$dimension == dimension_name,
    c("level_id", "label")
  ]
  labels <- setNames(lookup$label, lookup$level_id)
  scenario_matrix[[paste0(dimension_name, "_label")]] <-
    unname(labels[scenario_matrix[[dimension_name]]])
}

# DEC4 applies to the 2020-2050 run only: the runner sets these fix.100 values
# after copying the library files (spinup and history stages use the library).
if ("dec4" %in% names(scenario_matrix)) {
  unknown_dec4 <- setdiff(unique(scenario_matrix$dec4), names(dec4_values))
  if (length(unknown_dec4) > 0) {
    stop("No DEC4 value for levels: ", paste(unknown_dec4, collapse = ", "), call. = FALSE)
  }
  scenario_matrix$dec4_value <- unname(dec4_values[scenario_matrix$dec4])
  scenario_matrix$fix_overrides <- ifelse(
    scenario_matrix$dec4 == id_omitted_levels[["dec4"]],
    "",
    sprintf("DEC4=%.5f", scenario_matrix$dec4_value)
  )
} else {
  scenario_matrix$fix_overrides <- ""
}

scenario_matrix$is_project_scenario <- !scenario_matrix$conservation_practice %in% conventional_practices
scenario_matrix$scenario_role <- ifelse(
  scenario_matrix$is_project_scenario,
  "project_candidate",
  "reference_candidate"
)
scenario_matrix$counterfactual_rule <- "static_conventional_same_hlu_n_weather"

counterfactual_values <- scenario_matrix[, factor_dimensions, drop = FALSE]
counterfactual_values$conservation_practice <- "conv"
counterfactual_values$cycling_frequency <- "cont"
scenario_matrix$counterfactual_scenario_id <-
  make_scenario_id(counterfactual_values, factor_dimensions)

scenario_matrix$counterfactual_scenario_id[!scenario_matrix$is_project_scenario] <-
  scenario_matrix$scenario_id[!scenario_matrix$is_project_scenario]

scenario_id_set <- scenario_matrix$scenario_id
missing_counterfactuals <- setdiff(
  unique(scenario_matrix$counterfactual_scenario_id),
  scenario_id_set
)

if (length(missing_counterfactuals) > 0) {
  warning(
    "Some counterfactual IDs are not present in the generated matrix: ",
    paste(missing_counterfactuals, collapse = ", "),
    call. = FALSE
  )
}

front_columns <- c(
  "scenario_id",
  "site_id",
  "analysis_set",
  "scenario_role",
  "is_project_scenario",
  "counterfactual_scenario_id",
  "counterfactual_rule",
  factor_dimensions
)

scenario_matrix <- scenario_matrix[
  c(front_columns, setdiff(names(scenario_matrix), front_columns))
]

write.csv(scenario_matrix, output_path, row.names = FALSE)

message("Wrote ", nrow(scenario_matrix), " scenarios to ", output_path)
message("Factor dimensions included: ", paste(factor_dimensions, collapse = ", "))
