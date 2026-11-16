# Compile DayCent outputs into annual scenario summaries.
#
# This script is intentionally tolerant of partial results. It inventories
# output directories under sites/enfarm/outputs, compiles files that exist, and
# leaves missing model runs to the run-status workflow.

# Locate this script so paths work when it is run from RStudio or Rscript.
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

# Convert DayCent column names to simple snake_case names that are easier to use.
clean_names <- function(x) {
  x <- trimws(tolower(as.character(x)))
  x <- gsub("\\(", "_", x)
  x <- gsub("\\)", "", x)
  x <- gsub("[^a-z0-9]+", "_", x)
  x <- gsub("^_+|_+$", "", x)
  gsub("_+", "_", x)
}

# Read a DayCent CSV and immediately standardize its column names.
read_daycent_csv <- function(path) {
  df <- read.csv(
    path,
    check.names = FALSE,
    strip.white = TRUE,
    stringsAsFactors = FALSE
  )
  names(df) <- clean_names(names(df))
  df
}

# Store source file paths relative to the repository root for portable outputs.
rel_path <- function(path, root) {
  normalized_path <- normalizePath(path, winslash = "/", mustWork = FALSE)
  normalized_root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  sub(paste0("^", normalized_root, "/?"), "", normalized_path)
}

# Sum a set of pool columns, returning NA when any required pool is absent.
pool_sum <- function(df, cols) {
  if (!all(cols %in% names(df))) {
    return(rep(NA_real_, nrow(df)))
  }

  rowSums(df[, cols, drop = FALSE], na.rm = FALSE)
}

# Add accounting-relevant carbon pool totals and unit conversions to soil C data.
add_carbon_pools <- function(df) {
  df$somsc_g_c_m2 <- pool_sum(df, c("som1c_2", "som2c_2", "som3c"))
  df$nonactive_soilc_g_c_m2 <- pool_sum(df, c("som2c_2", "som3c"))
  df$nonactive_oc_g_c_m2 <- pool_sum(df, c("som2c_1", "som2c_2", "som3c"))
  df$soil_surface_som_c_g_c_m2 <- pool_sum(
    df,
    c("som1c_1", "som1c_2", "som2c_1", "som2c_2", "som3c")
  )
  df$mineral_soc_with_litter_g_c_m2 <- pool_sum(
    df,
    c("metabc_2", "strucc_2", "som1c_2", "som2c_2", "som3c")
  )
  df$surface_organic_c_g_c_m2 <- pool_sum(
    df,
    c("metabc_1", "strucc_1", "som1c_1", "som2c_1")
  )
  df$total_soil_surface_organic_c_g_c_m2 <- pool_sum(
    df,
    c(
      "metabc_1", "metabc_2",
      "strucc_1", "strucc_2",
      "som1c_1", "som1c_2",
      "som2c_1", "som2c_2",
      "som3c"
    )
  )

  carbon_pool_cols <- grep("_g_c_m2$", names(df), value = TRUE)
  for (col in carbon_pool_cols) {
    mg_c_col <- sub("_g_c_m2$", "_mg_c_ha", col)
    mg_co2e_col <- sub("_g_c_m2$", "_mg_co2e_ha", col)
    df[[mg_c_col]] <- df[[col]] * 0.01
    df[[mg_co2e_col]] <- df[[mg_c_col]] * 44 / 12
  }

  df
}

# Reduce stock outputs to one annual snapshot near the start of each model year.
annual_stock_snapshot <- function(df) {
  if (!("time" %in% names(df))) {
    stop("Expected a time column in stock output.", call. = FALSE)
  }

  df <- df[order(df$time), ]
  df$year <- floor(df$time + 1e-8)
  split_df <- split(df, df$year)
  annual <- do.call(rbind, lapply(split_df, function(year_df) {
    target_year <- unique(year_df$year)[1]
    year_df[which.min(abs(year_df$time - target_year)), , drop = FALSE]
  }))
  row.names(annual) <- NULL
  annual$snapshot_time <- annual$time
  annual
}

# Sum event or flux variables by model year.
sum_by_year <- function(df, value_cols) {
  if (length(value_cols) == 0) {
    return(data.frame())
  }

  df$year <- floor(df$time + 1e-8)
  aggregate(
    df[, value_cols, drop = FALSE],
    by = list(year = df$year),
    FUN = function(x) sum(x, na.rm = TRUE)
  )
}

# Compile one soilc output into annual stock summaries and derived C pools.
compile_soilc <- function(path) {
  df <- read_daycent_csv(path)
  df <- add_carbon_pools(df)
  annual <- annual_stock_snapshot(df)

  keep_cols <- c(
    "year", "snapshot_time",
    grep(
      "_g_c_m2$|_mg_c_ha$|_mg_co2e_ha$",
      names(annual),
      value = TRUE
    )
  )
  annual[, keep_cols, drop = FALSE]
}

# Compile one harvest output into annual production, residue, and fertilizer totals.
compile_harvest <- function(path) {
  df <- read_daycent_csv(path)
  if (!("time" %in% names(df))) {
    stop("Expected a time column in harvest output.", call. = FALSE)
  }

  value_cols <- intersect(
    c(
      "agcacc", "bgcjacc", "bgcmacc",
      "cgrain", "crmvst", "cstraw",
      "addsdc", "resid", "cgracc", "accrst",
      "fertapp_n"
    ),
    names(df)
  )

  annual <- sum_by_year(df, value_cols)
  if (nrow(annual) == 0) {
    return(annual)
  }

  names(annual)[names(annual) != "year"] <-
    paste0("annual_", names(annual)[names(annual) != "year"])

  if (all(c("annual_cgracc", "annual_accrst") %in% names(annual))) {
    annual$annual_harvest_c_g_c_m2 <-
      annual$annual_cgracc + annual$annual_accrst
    annual$annual_harvest_c_mg_c_ha <-
      annual$annual_harvest_c_g_c_m2 * 0.01
  }

  annual
}

# Compile one N flux output into annual N2O-N, N2O mass, and CO2e emissions.
compile_nflux <- function(path, n2o_gwp = 298) {
  df <- read_daycent_csv(path)
  if (!("time" %in% names(df))) {
    stop("Expected a time column in N flux output.", call. = FALSE)
  }

  n2o_component_cols <- intersect(
    c("nit_n2o_n_gn_ha", "dnit_n2o_n_gn_ha"),
    names(df)
  )

  if (length(n2o_component_cols) > 0) {
    df$n2o_n_gn_ha <- rowSums(df[, n2o_component_cols, drop = FALSE], na.rm = TRUE)
    annual <- sum_by_year(df, "n2o_n_gn_ha")
    names(annual)[names(annual) == "n2o_n_gn_ha"] <- "annual_n2o_n_gn_ha"
  } else if ("cum_n2o_gn_ha" %in% names(df)) {
    df$year <- floor(df$time + 1e-8)
    annual <- aggregate(
      df$cum_n2o_gn_ha,
      by = list(year = df$year),
      FUN = function(x) max(x, na.rm = TRUE) - min(x, na.rm = TRUE)
    )
    names(annual)[names(annual) == "x"] <- "annual_n2o_n_gn_ha"
  } else {
    annual <- data.frame()
  }

  if (nrow(annual) == 0) {
    return(annual)
  }

  # N flux files report N2O-N, so convert N mass to N2O mass with 44/28.
  annual$annual_n2o_mg_n2o_ha <- annual$annual_n2o_n_gn_ha * 44 / 28 / 1e6
  annual$annual_n2o_co2e_mg_ha <- annual$annual_n2o_mg_n2o_ha * n2o_gwp
  annual$n2o_gwp <- n2o_gwp

  # NO3 leaching drives indirect N2O in the accounting step.
  if ("no3_n_leach_gn_m2" %in% names(df)) {
    leach <- sum_by_year(df, "no3_n_leach_gn_m2")
    names(leach)[names(leach) == "no3_n_leach_gn_m2"] <- "annual_no3_leach_n_g_m2"
    annual <- merge(annual, leach, by = "year", all.x = TRUE)
  }
  annual
}

# Compile one list100 binpools table (from extract_bin_pools.R) into annual
# somtc, totc, and totsysc stocks plus annual N volatilization.
compile_binpools <- function(path) {
  df <- read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  df <- df[order(df$year), , drop = FALSE]
  annual <- data.frame(
    year = df$year,
    somtc_g_c_m2 = df$somtc,
    totc_g_c_m2 = df$totc,
    totsysc_g_c_m2 = df$totsysc
  )
  for (col in c("somtc_g_c_m2", "totc_g_c_m2", "totsysc_g_c_m2")) {
    mg_c_col <- sub("_g_c_m2$", "_mg_c_ha", col)
    annual[[mg_c_col]] <- annual[[col]] * 0.01
    annual[[sub("_g_c_m2$", "_mg_co2e_ha", col)]] <- annual[[mg_c_col]] * 44 / 12
  }

  # Accumulators are cumulative from the exp-run start; a year's volatilization
  # is the change from its start-of-year snapshot to the next one.
  cumulative_vol <- df$volgma + df$volexa + df$volpla
  next_year_index <- match(df$year + 1L, df$year)
  annual$annual_volatilized_n_g_m2 <- cumulative_vol[next_year_index] - cumulative_vol
  annual
}

# Find the expected output file for a run, allowing legacy names as a fallback.
find_output_file <- function(run_dir, run_id, output_type) {
  exact_path <- file.path(run_dir, paste0(run_id, "_", output_type, ".csv"))
  if (file.exists(exact_path)) {
    return(exact_path)
  }

  candidates <- list.files(
    run_dir,
    pattern = paste0("_", output_type, "\\.csv$"),
    full.names = TRUE
  )

  if (length(candidates) == 0) {
    return(NA_character_)
  }

  candidates[1]
}

# Join soil, harvest, and N flux annual tables for a single run.
merge_annual_tables <- function(tables) {
  tables <- Filter(function(x) !is.null(x) && nrow(x) > 0, tables)
  if (length(tables) == 0) {
    return(data.frame())
  }

  Reduce(function(x, y) merge(x, y, by = "year", all = TRUE), tables)
}

# Row-bind tables with different columns by filling missing fields with NA.
rbind_fill <- function(tables) {
  tables <- Filter(function(x) !is.null(x) && nrow(x) > 0, tables)
  if (length(tables) == 0) {
    return(data.frame())
  }

  all_cols <- unique(unlist(lapply(tables, names), use.names = FALSE))
  filled <- lapply(tables, function(df) {
    missing_cols <- setdiff(all_cols, names(df))
    for (col in missing_cols) {
      df[[col]] <- NA
    }
    df[, all_cols, drop = FALSE]
  })

  do.call(rbind, filled)
}

# Compile all available outputs for one run directory into one annual table.
compile_run <- function(run_dir, repo_root) {
  run_id <- basename(run_dir)

  soilc_path <- find_output_file(run_dir, run_id, "soilc")
  harvest_path <- find_output_file(run_dir, run_id, "harvest")
  nflux_path <- find_output_file(run_dir, run_id, "nflux")

  run_tables <- list()
  if (!is.na(soilc_path)) {
    run_tables$soilc <- compile_soilc(soilc_path)
  }
  if (!is.na(harvest_path)) {
    run_tables$harvest <- compile_harvest(harvest_path)
  }
  if (!is.na(nflux_path)) {
    run_tables$nflux <- compile_nflux(nflux_path)
  }
  binpools_path <- find_output_file(run_dir, run_id, "binpools")
  if (!is.na(binpools_path) && !is.null(run_tables$soilc)) {
    binpools <- compile_binpools(binpools_path)
    run_tables$binpools <- binpools[binpools$year %in% run_tables$soilc$year, , drop = FALSE]
  }

  annual <- merge_annual_tables(run_tables)
  if (nrow(annual) == 0) {
    return(data.frame())
  }

  annual$scenario_id <- run_id
  annual$site_id <- "enfarm"
  annual$source_output_dir <- rel_path(run_dir, repo_root)
  annual$soilc_file <- ifelse(is.na(soilc_path), NA_character_, rel_path(soilc_path, repo_root))
  annual$harvest_file <- ifelse(is.na(harvest_path), NA_character_, rel_path(harvest_path, repo_root))
  annual$nflux_file <- ifelse(is.na(nflux_path), NA_character_, rel_path(nflux_path, repo_root))

  front_cols <- c(
    "scenario_id", "site_id", "year", "snapshot_time",
    "source_output_dir", "soilc_file", "harvest_file", "nflux_file"
  )
  annual[, c(front_cols, setdiff(names(annual), front_cols)), drop = FALSE]
}

# Summarize which expected output types are available for each run directory.
build_run_inventory <- function(output_dirs, repo_root) {
  rows <- lapply(output_dirs, function(run_dir) {
    run_id <- basename(run_dir)
    data.frame(
      scenario_id = run_id,
      source_output_dir = rel_path(run_dir, repo_root),
      has_soilc = !is.na(find_output_file(run_dir, run_id, "soilc")),
      has_harvest = !is.na(find_output_file(run_dir, run_id, "harvest")),
      has_nflux = !is.na(find_output_file(run_dir, run_id, "nflux")),
      has_binpools = !is.na(find_output_file(run_dir, run_id, "binpools")),
      stringsAsFactors = FALSE
    )
  })

  do.call(rbind, rows)
}

script_dir <- get_script_dir()
repo_root <- normalizePath(file.path(script_dir, ".."), mustWork = TRUE)
outputs_dir <- file.path(repo_root, "sites", "enfarm", "outputs")
summary_dir <- file.path(repo_root, "outputs", "summary")

if (!dir.exists(summary_dir)) {
  dir.create(summary_dir, recursive = TRUE)
}

output_dirs <- list.dirs(outputs_dir, recursive = FALSE, full.names = TRUE)
if (length(output_dirs) == 0) {
  stop("No output directories found under ", outputs_dir, call. = FALSE)
}

compiled_runs <- lapply(output_dirs, compile_run, repo_root = repo_root)
annual_summary <- rbind_fill(compiled_runs)

inventory <- build_run_inventory(output_dirs, repo_root)

scenario_matrix_path <- file.path(repo_root, "analysis", "scenario_matrix.csv")
if (file.exists(scenario_matrix_path) && nrow(annual_summary) > 0) {
  scenario_matrix <- read.csv(
    scenario_matrix_path,
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  metadata_cols <- setdiff(
    names(scenario_matrix),
    c("schedule_file", "output_dir")
  )
  annual_summary <- merge(
    annual_summary,
    scenario_matrix[, metadata_cols, drop = FALSE],
    by = c("scenario_id", "site_id"),
    all.x = TRUE
  )
}

annual_path <- file.path(summary_dir, "daycent_annual_summary.csv")
inventory_path <- file.path(summary_dir, "daycent_output_inventory.csv")

write.csv(annual_summary, annual_path, row.names = FALSE)
write.csv(inventory, inventory_path, row.names = FALSE)

message("Compiled ", nrow(annual_summary), " annual rows.")
message("Wrote annual summary to ", annual_path)
message("Wrote output inventory to ", inventory_path)
