# Calculate annualized credit values for every project scenario under every
# accounting rule.
#
# Edit analysis/accounting_options.csv to add, remove, or deactivate options.
# This script crosses the active options into analysis/accounting_rules.csv and
# writes outputs/summary/accounting_results.csv with one row per project
# scenario x rule.
#
# All amounts are reported per year (Mg CO2e/ha/yr = total / horizon). Soil
# pools cover 0-20 cm (fix.100 EDEPTH = 0.20 m); totc and totsysc also include
# surface (and, for totsysc, live plant) C.
#
# Functional unit (accounting dimension):
# - area: credit per hectare = (project - counterfactual) stock change and N2O.
# - bushel: carbon-intensity crediting, as in FD-CIC and fuel CI scoring. Each
#   system's emissions over the horizon, E = -stock change x 44/12 + N2O (CO2e,
#   per ha; N2O only when the N2O option counts it), are divided by that
#   system's own corn bushels over the same years: CI = E / bushels. Credit per
#   bushel = CI_counterfactual - CI_project (kg CO2e/bu). The area-equivalent,
#   credit per bushel x project bushels/ha/yr, is reported in the per-area
#   columns so both units share one scale: it equals the area credit plus
#   E_counterfactual x (project bushels / counterfactual bushels - 1), i.e. it
#   differs from the area credit only when the practice changes yield.
#
# Counterfactuals: each option in accounting_options.csv names a conventional
# practice (conv, convplow, convrt); the project is compared with it under
# continuous management at the same N rate, history, weather, and DEC4.
# Every row also reports net_credit_kg_co2e_bu: the per-bushel credit for
# "bushel", and the area credit over project bushels for "area".

library(data.table)

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
options_path <- file.path(repo_root, "analysis", "accounting_options.csv")
rules_path <- file.path(repo_root, "analysis", "accounting_rules.csv")
matrix_path <- file.path(repo_root, "analysis", "scenario_matrix.csv")
summary_path <- file.path(repo_root, "outputs", "summary", "daycent_annual_summary.csv")
results_path <- file.path(repo_root, "outputs", "summary", "accounting_results.csv")

start_year <- 2020L
soil_depth_cm <- 20L
c_to_co2 <- 44 / 12
n2o_n_to_n2o <- 44 / 28

# IPCC 2019 Refinement Tier 1 indirect N2O parameters (Vol. 4, Ch. 11, Table 11.3).
# DayCent-CABBI does not simulate fertilizer NH3 volatilization (volgma and
# volexa are zero), so volatilization uses the Tier 1 fraction of applied N.
ef4_volatilization <- 0.010   # kg N2O-N per kg NH3-N + NOx-N volatilized
ef5_leaching <- 0.011         # kg N2O-N per kg N leached
frac_gasf_synthetic <- 0.11   # fraction of synthetic fertilizer N volatilized

# Corn grain C (DayCent cgrain, g C/m2, dry matter) to bushels. The C fraction
# and bushel weight are from RunDaycent.Rmd (convert_corn_gC_to_MJ); a 56 lb
# bushel is at 15.5% moisture, so it holds 25.4 x (1 - 0.155) = 21.46 kg of
# dry grain (RunDaycent.Rmd divided dry grain by 25.4 kg, which counts ~15%
# fewer bushels).
grain_c_fraction <- 0.435     # g C per g dry grain (Gescha et al., 2010)
bushel_kg <- 56 * 0.45359237  # 25.40 kg per bushel of shelled corn at standard moisture
bushel_moisture <- 0.155      # standard moisture of a corn bushel
dry_kg_per_bushel <- bushel_kg * (1 - bushel_moisture)
bushels_per_g_c_m2 <- 10 / grain_c_fraction / dry_kg_per_bushel   # g C/m2 -> bu/ha

# Build the rule table from active options --------------------------------

accounting_options <- fread(options_path, colClasses = "character")
accounting_options[, active := toupper(trimws(active)) %in% c("TRUE", "T", "1", "YES")]
active_options <- accounting_options[active == TRUE]
options_for <- function(dimension_name) {
  active_options[dimension == dimension_name]
}

pools <- options_for("carbon_pool")
horizons <- options_for("horizon")
counterfactuals <- options_for("counterfactual")
n2o_options <- options_for("n2o")
functional_units <- options_for("functional_unit")
unknown_units <- setdiff(functional_units$option_id, c("area", "bushel"))
if (length(unknown_units) > 0) {
  stop("No functional-unit definition in this script for: ", paste(unknown_units, collapse = ", "),
       call. = FALSE)
}
for (dimension_name in c("carbon_pool", "horizon", "counterfactual", "n2o", "functional_unit")) {
  if (nrow(options_for(dimension_name)) == 0) {
    stop("No active accounting options for: ", dimension_name, call. = FALSE)
  }
}
# Each counterfactual option names a conventional practice (its value column):
# the project is compared with that practice under continuous management at the
# project's N rate, history, weather, and DEC4.
if (any(!nzchar(counterfactuals$value))) {
  stop("Every counterfactual option needs a conventional practice in its value column.", call. = FALSE)
}

rules <- CJ(
  carbon_pool = pools$option_id,
  horizon = horizons$option_id,
  counterfactual = counterfactuals$option_id,
  n2o_option = n2o_options$option_id,
  functional_unit = functional_units$option_id,
  sorted = FALSE
)
rules[pools, on = c(carbon_pool = "option_id"),
      `:=`(carbon_pool_label = i.label, pool_column = i.value, pool_notes = i.notes)]
rules[horizons, on = c(horizon = "option_id"), horizon_years := as.integer(i.value)]
rules[counterfactuals, on = c(counterfactual = "option_id"), counterfactual_label := i.label]
rules[n2o_options, on = c(n2o_option = "option_id"),
      `:=`(n2o_label = i.label, n2o_gwp = as.numeric(i.value), n2o_scope = i.n2o_scope)]
rules[functional_units, on = c(functional_unit = "option_id"), functional_unit_label := i.label]
rules[, rule_id := paste(carbon_pool, horizon, counterfactual, n2o_option, functional_unit, sep = "__")]
rules[, soil_depth_cm := soil_depth_cm]
setcolorder(rules, c("rule_id", "carbon_pool", "carbon_pool_label", "pool_column",
                     "horizon", "horizon_years", "counterfactual", "counterfactual_label",
                     "n2o_option", "n2o_label", "n2o_scope", "n2o_gwp",
                     "functional_unit", "functional_unit_label", "soil_depth_cm", "pool_notes"))
fwrite(rules, rules_path)

# Load annual trajectories -------------------------------------------------

annual <- fread(summary_path)
scenario_matrix <- fread(matrix_path)
max_horizon <- max(rules$horizon_years)
needed_years <- start_year:(start_year + max_horizon)
pool_columns <- unique(rules$pool_column)
flux_columns <- c("annual_n2o_n_gn_ha", "annual_no3_leach_n_g_m2", "annual_fertapp_n", "annual_cgrain")
missing_columns <- setdiff(c(pool_columns, flux_columns), names(annual))
if (length(missing_columns) > 0) {
  stop("Annual summary is missing columns: ", paste(missing_columns, collapse = ", "),
       ". Run extract_bin_pools.R and compile_outputs.R first.", call. = FALSE)
}

annual <- annual[scenario_id %in% scenario_matrix$scenario_id & year %in% needed_years,
                 c("scenario_id", "year", pool_columns, flux_columns), with = FALSE]
coverage <- annual[, .N, by = scenario_id]
incomplete <- setdiff(scenario_matrix$scenario_id,
                      coverage[N == length(needed_years), scenario_id])
if (length(incomplete) > 0) {
  stop(length(incomplete), " scenarios lack complete ", min(needed_years), "-",
       max(needed_years), " data, e.g. ", paste(head(incomplete, 3), collapse = ", "),
       call. = FALSE)
}
if (anyNA(annual)) {
  stop("Annual trajectories contain missing values.", call. = FALSE)
}

# Annual direct and indirect N2O-N in g N/ha (g N/m2 x 1e4 = g N/ha).
annual[, direct_n2o_n_g_ha := annual_n2o_n_gn_ha]
annual[, indirect_n2o_n_g_ha := 1e4 * (
  annual_no3_leach_n_g_m2 * ef5_leaching +
    annual_fertapp_n * frac_gasf_synthetic * ef4_volatilization
)]

# Stock change and cumulative N2O-N for each scenario and horizon -----------

horizon_values <- sort(unique(rules$horizon_years))
start_stocks <- annual[year == start_year, c("scenario_id", pool_columns), with = FALSE]
per_horizon <- rbindlist(lapply(horizon_values, function(h) {
  end_stocks <- annual[year == start_year + h, c("scenario_id", pool_columns), with = FALSE]
  stock_change <- melt(end_stocks, id.vars = "scenario_id",
                       variable.name = "pool_column", value.name = "end_stock")
  stock_change[melt(start_stocks, id.vars = "scenario_id",
                    variable.name = "pool_column", value.name = "start_stock"),
               on = c("scenario_id", "pool_column"), start_stock := i.start_stock]
  stock_change[, delta_stock_mg_c_ha := end_stock - start_stock]

  # N2O accumulates over full model years start_year through endpoint - 1.
  # Corn bushels harvested over the same model years.
  n2o <- annual[year >= start_year & year < start_year + h,
                .(direct_n2o_n_g_ha = sum(direct_n2o_n_g_ha),
                  indirect_n2o_n_g_ha = sum(indirect_n2o_n_g_ha),
                  corn_bu_ha = sum(annual_cgrain) * bushels_per_g_c_m2),
                by = scenario_id]
  stock_change[n2o, on = "scenario_id",
               `:=`(direct_n2o_n_g_ha = i.direct_n2o_n_g_ha,
                    indirect_n2o_n_g_ha = i.indirect_n2o_n_g_ha,
                    corn_bu_ha = i.corn_bu_ha)]
  stock_change[, horizon_years := h]
  stock_change[, c("end_stock", "start_stock") := NULL]
  stock_change
}))
per_horizon[, pool_column := as.character(pool_column)]

# Pair each project with its counterfactual scenarios ----------------------

match_keys <- c("n_rate", "historic_land_use", "weather_sequence", "dec4")
projects <- scenario_matrix[is_project_scenario == TRUE,
                            c("scenario_id", "conservation_practice", "cycling_frequency",
                              match_keys), with = FALSE]
references <- scenario_matrix[cycling_frequency == "cont" & conservation_practice %in% counterfactuals$value,
                              c("scenario_id", "conservation_practice", match_keys), with = FALSE]
setnames(references, c("scenario_id", "conservation_practice"), c("counterfactual_scenario_id", "reference_practice"))
pairs <- rbindlist(lapply(seq_len(nrow(counterfactuals)), function(k) {
  cf <- counterfactuals[k]
  p <- merge(projects, references[reference_practice == cf$value], by = match_keys)
  p[, counterfactual := cf$option_id][, reference_practice := NULL]
}))
# Every project needs every counterfactual.
incomplete <- pairs[, .N, by = scenario_id][N < nrow(counterfactuals)]
unpaired <- setdiff(projects$scenario_id, pairs$scenario_id)
if (nrow(incomplete) > 0 || length(unpaired) > 0) {
  stop("Projects without every counterfactual, e.g. ",
       paste(head(c(incomplete$scenario_id, unpaired), 3), collapse = ", "), call. = FALSE)
}

# Expand to every rule and compute credits ----------------------------------

results <- rules[pairs, on = "counterfactual", allow.cartesian = TRUE]
results[per_horizon, on = c(scenario_id = "scenario_id", pool_column = "pool_column",
                            horizon_years = "horizon_years"),
        `:=`(delta_stock_project_mg_c_ha = i.delta_stock_mg_c_ha,
             direct_n2o_project = i.direct_n2o_n_g_ha,
             indirect_n2o_project = i.indirect_n2o_n_g_ha,
             corn_bu_ha_project = i.corn_bu_ha)]
results[per_horizon, on = c(counterfactual_scenario_id = "scenario_id",
                            pool_column = "pool_column", horizon_years = "horizon_years"),
        `:=`(delta_stock_counterfactual_mg_c_ha = i.delta_stock_mg_c_ha,
             direct_n2o_counterfactual = i.direct_n2o_n_g_ha,
             indirect_n2o_counterfactual = i.indirect_n2o_n_g_ha,
             corn_bu_ha_counterfactual = i.corn_bu_ha)]
if (any(results$corn_bu_ha_project <= 0) || any(results$corn_bu_ha_counterfactual <= 0)) {
  stop("Some scenarios harvest no corn over a horizon; per-bushel credits are undefined.", call. = FALSE)
}

# Counted N2O-N (g N/ha over the horizon) for each system under the rule.
counted_n2o <- function(direct, indirect, scope) {
  fifelse(scope == "none", 0, direct + fifelse(scope == "direct_indirect", indirect, 0))
}
results[, `:=`(
  n2o_n_project_g_ha = counted_n2o(direct_n2o_project, indirect_n2o_project, n2o_scope),
  n2o_n_counterfactual_g_ha = counted_n2o(direct_n2o_counterfactual, indirect_n2o_counterfactual, n2o_scope)
)]
n2o_to_mg_co2e <- function(n_g_ha, gwp) n_g_ha * n2o_n_to_n2o / 1e6 * gwp

# Per area: project minus counterfactual.
results[, `:=`(
  soc_benefit_mg_co2e_ha_yr =
    (delta_stock_project_mg_c_ha - delta_stock_counterfactual_mg_c_ha) * c_to_co2 / horizon_years,
  n2o_increase_mg_co2e_ha_yr =
    n2o_to_mg_co2e(n2o_n_project_g_ha - n2o_n_counterfactual_g_ha, n2o_gwp) / horizon_years
)]

# Per bushel (carbon intensity): the counterfactual's SOC change and N2O are
# scaled to project production before differencing (area-equivalent), and
# the per-bushel credit is that total over project bushels.
results[functional_unit == "bushel", yield_ratio := corn_bu_ha_project / corn_bu_ha_counterfactual]
results[functional_unit == "bushel", `:=`(
  soc_benefit_mg_co2e_ha_yr =
    (delta_stock_project_mg_c_ha - delta_stock_counterfactual_mg_c_ha * yield_ratio) * c_to_co2 / horizon_years,
  n2o_increase_mg_co2e_ha_yr =
    n2o_to_mg_co2e(n2o_n_project_g_ha - n2o_n_counterfactual_g_ha * yield_ratio, n2o_gwp) / horizon_years
)]
results[, net_credit_mg_co2e_ha_yr := soc_benefit_mg_co2e_ha_yr - n2o_increase_mg_co2e_ha_yr]
results[, net_credit_total_mg_co2e_ha := net_credit_mg_co2e_ha_yr * horizon_years]
results[, net_credit_kg_co2e_bu := 1000 * net_credit_total_mg_co2e_ha / corn_bu_ha_project]
results[, `:=`(corn_bu_ha_yr_project = corn_bu_ha_project / horizon_years,
               corn_bu_ha_yr_counterfactual = corn_bu_ha_counterfactual / horizon_years)]

if (anyNA(results$net_credit_mg_co2e_ha_yr) || anyNA(results$net_credit_kg_co2e_bu)) {
  stop("Some credit values could not be calculated.", call. = FALSE)
}

# rule_id and soil_depth_cm (constant) are in accounting_rules.csv; the rule's
# dimensions are columns here.
results <- results[, .(
  scenario_id, conservation_practice, n_rate, historic_land_use,
  cycling_frequency, weather_sequence, dec4, carbon_pool, horizon_years, counterfactual,
  n2o_option, functional_unit, counterfactual_scenario_id,
  delta_stock_project_mg_c_ha, delta_stock_counterfactual_mg_c_ha,
  corn_bu_ha_yr_project, corn_bu_ha_yr_counterfactual,
  soc_benefit_mg_co2e_ha_yr, n2o_increase_mg_co2e_ha_yr,
  net_credit_mg_co2e_ha_yr, net_credit_total_mg_co2e_ha, net_credit_kg_co2e_bu
)]
# Six significant digits keep the file under GitHub's 100 MB limit.
numeric_columns <- names(results)[vapply(results, is.double, logical(1))]
results[, (numeric_columns) := lapply(.SD, signif, digits = 6), .SDcols = numeric_columns]
setorder(results, scenario_id, carbon_pool, horizon_years, counterfactual, n2o_option, functional_unit)
fwrite(results, results_path)

message("Wrote ", nrow(rules), " accounting rules to ", rules_path)
message("Wrote ", nrow(results), " credit values (", uniqueN(results$scenario_id),
        " project scenarios) to ", results_path)
