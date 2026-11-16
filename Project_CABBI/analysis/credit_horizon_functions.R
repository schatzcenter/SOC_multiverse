# Net credit for every horizon (years from 2020) from the annual stocks and
# fluxes, with the definitions of calculate_credit_values.R: stock change from
# the 2020 start-of-year stock to the start of 2020 + h; N2O and corn bushels
# summed over model years 2020 through 2020 + h - 1; counterfactuals (each a
# conventional practice at the project's N rate, history, weather, and DEC4);
# N2O options; per-area and per-bushel (carbon intensity) units.
# Sourced by credit_horizon_curves.R and plausible_sets.R.
#
# horizon_credits(repo_root, horizons, pools, counterfactuals, n2o_options,
#                 units, analysis_sets): option IDs default to every active
#                 option in accounting_options.csv (horizon options there are
#                 ignored); analysis_sets limits the projects (e.g.
#                 "sensitivity"; NULL = all). Projects are paired only with
#                 counterfactual runs that exist.
# Returns one row per project scenario x carbon pool x counterfactual x N2O
# option x functional unit x horizon h, with net_total (Mg CO2e/ha over the
# horizon), net_annual (Mg CO2e/ha/yr), and bu_p (project bushels/ha over the
# horizon).

library(data.table)

horizon_credits <- function(repo_root, horizons = 1:30, pools = NULL, counterfactuals = NULL,
                            n2o_options = NULL, units = NULL, analysis_sets = NULL) {
  start_year <- 2020L
  c_to_co2 <- 44 / 12
  n2o_n_to_n2o <- 44 / 28
  # As in calculate_credit_values.R
  ef4_volatilization <- 0.010
  ef5_leaching <- 0.011
  frac_gasf_synthetic <- 0.11
  grain_c_fraction <- 0.435
  dry_kg_per_bushel <- 56 * 0.45359237 * (1 - 0.155)
  bushels_per_g_c_m2 <- 10 / grain_c_fraction / dry_kg_per_bushel

  opts <- fread(file.path(repo_root, "analysis", "accounting_options.csv"), colClasses = "character")
  pick <- function(dimension_name, ids) {
    o <- opts[dimension == dimension_name]
    if (is.null(ids)) return(o[toupper(trimws(active)) %in% c("TRUE", "T", "1", "YES")])
    missing <- setdiff(ids, o$option_id)
    if (length(missing) > 0) stop("Unknown ", dimension_name, " options: ", paste(missing, collapse = ", "), call. = FALSE)
    o[option_id %in% ids]
  }
  pool_opts <- pick("carbon_pool", pools)[, .(carbon_pool = option_id, pool_column = value)]
  n2o_opts <- pick("n2o", n2o_options)[, .(n2o_option = option_id, n2o_gwp = as.numeric(value), n2o_scope)]
  cf_opts <- pick("counterfactual", counterfactuals)[, .(option_id, value)]
  unit_opts <- pick("functional_unit", units)$option_id

  # Annual series
  scenario_matrix <- fread(file.path(repo_root, "analysis", "scenario_matrix.csv"))
  annual <- fread(file.path(repo_root, "outputs", "summary", "daycent_annual_summary.csv"))
  annual <- annual[scenario_id %in% scenario_matrix$scenario_id & year %in% start_year:(start_year + max(horizons)),
                   c("scenario_id", "year", pool_opts$pool_column, "annual_n2o_n_gn_ha", "annual_no3_leach_n_g_m2",
                     "annual_fertapp_n", "annual_cgrain"), with = FALSE]
  if (annual[, .N, by = scenario_id][, any(N != max(horizons) + 1L)]) {
    stop("Incomplete annual series for ", start_year, "-", start_year + max(horizons), ".", call. = FALSE)
  }
  setorder(annual, scenario_id, year)
  annual[, `:=`(direct = annual_n2o_n_gn_ha,
                indirect = 1e4 * (annual_no3_leach_n_g_m2 * ef5_leaching +
                                    annual_fertapp_n * frac_gasf_synthetic * ef4_volatilization),
                bushels = annual_cgrain * bushels_per_g_c_m2)]

  # Per scenario, pool, and horizon: stock change and cumulative N2O-N and bushels
  long <- melt(annual, id.vars = c("scenario_id", "year", "direct", "indirect", "bushels"),
               measure.vars = pool_opts$pool_column, variable.name = "pool_column", value.name = "stock")
  long[, pool_column := as.character(pool_column)]
  setorder(long, scenario_id, pool_column, year)
  long[, `:=`(h = year - start_year,
              delta_stock = stock - stock[1],
              cum_direct = cumsum(shift(direct, fill = 0)),      # model years start .. start + h - 1
              cum_indirect = cumsum(shift(indirect, fill = 0)),
              cum_bushels = cumsum(shift(bushels, fill = 0))), by = .(scenario_id, pool_column)]
  traj <- long[h %in% horizons, .(scenario_id, pool_column, h, delta_stock, cum_direct, cum_indirect, cum_bushels)]

  # Project / counterfactual pairs: each counterfactual option names a
  # conventional practice, run continuously at the project's N rate, history,
  # weather, and DEC4 (as in calculate_credit_values.R)
  match_keys <- c("n_rate", "historic_land_use", "weather_sequence", "dec4")
  projects <- scenario_matrix[is_project_scenario == TRUE,
                              c("scenario_id", "analysis_set", "conservation_practice", "cycling_frequency",
                                match_keys), with = FALSE]
  if (!is.null(analysis_sets)) projects <- projects[analysis_set %in% analysis_sets]
  references <- scenario_matrix[cycling_frequency == "cont" & conservation_practice %in% cf_opts$value,
                                c("scenario_id", "conservation_practice", match_keys), with = FALSE]
  setnames(references, c("scenario_id", "conservation_practice"), c("counterfactual_scenario_id", "reference_practice"))
  pairs <- rbindlist(lapply(seq_len(nrow(cf_opts)), function(k) {
    p <- merge(projects, references[reference_practice == cf_opts$value[k]], by = match_keys)
    p[, counterfactual := cf_opts$option_id[k]][, reference_practice := NULL]
  }))

  grid <- CJ(pair = seq_len(nrow(pairs)), pool_column = pool_opts$pool_column, h = horizons)
  grid <- cbind(pairs[grid$pair], grid[, .(pool_column, h)])
  grid[traj, on = c("scenario_id", "pool_column", "h"),
       `:=`(dp = i.delta_stock, np_dir = i.cum_direct, np_ind = i.cum_indirect, bu_p = i.cum_bushels)]
  grid[traj, on = c(counterfactual_scenario_id = "scenario_id", "pool_column", "h"),
       `:=`(dc = i.delta_stock, nc_dir = i.cum_direct, nc_ind = i.cum_indirect, bu_c = i.cum_bushels)]
  grid[pool_opts, on = "pool_column", carbon_pool := i.carbon_pool]

  credits <- rbindlist(lapply(seq_len(nrow(n2o_opts)), function(k) {
    o <- n2o_opts[k]
    counted <- function(dir, ind) {
      if (o$n2o_scope == "none") 0 else dir + if (o$n2o_scope == "direct_indirect") ind else 0
    }
    to_co2e <- function(n) n * n2o_n_to_n2o / 1e6 * o$n2o_gwp
    rbindlist(lapply(unit_opts, function(u) {
      g <- copy(grid)
      ratio <- if (u == "bushel") g[, bu_p / bu_c] else 1
      g[, net_total := (dp - dc * ratio) * c_to_co2 - to_co2e(counted(np_dir, np_ind) - counted(nc_dir, nc_ind) * ratio)]
      g[, `:=`(n2o_option = o$n2o_option, functional_unit = u)]
      g[, .(scenario_id, analysis_set, conservation_practice, n_rate, historic_land_use, cycling_frequency, dec4,
            carbon_pool, counterfactual, n2o_option, functional_unit, h, net_total, bu_p)]
    }))
  }))
  credits[, net_annual := net_total / h]
  if (anyNA(credits$net_total)) stop("Some credits could not be calculated.", call. = FALSE)
  credits[]
}
