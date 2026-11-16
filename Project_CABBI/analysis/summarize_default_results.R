# Summary table of the default scenarios (UAN20, site-specific history,
# continuous management, observed weather): net SOC accumulation of each
# conservation practice relative to conventional, per hectare, per year, per
# bushel of corn, and per MJ of corn ethanol.
#
# Definitions (somsc, 0-20 cm; 2020 -> 2050, start-of-year stocks; conventional
# = continuous default conventional at the same N rate and history, cf_conv):
#   net SOC accumulation  = (somsc 2050 - somsc 2020)_practice - (same)_conventional
#   average net SOC gain  = net SOC accumulation / 30
#   per bushel            = net SOC accumulation / the practice's corn bushels
#                           harvested 2020-2049
#   per MJ ethanol        = net SOC accumulation / ethanol energy from those
#                           bushels
# Corn grain C (DayCent cgrain, dry matter) -> bushels and ethanol, following
# RunDaycent.Rmd (convert_corn_gC_to_MJ): 0.435 g C/g grain (Gescha et al.,
# 2010); 56 lb (25.40 kg) bushel at 15.5% moisture = 21.46 kg dry grain
# (RunDaycent.Rmd divided dry grain by 25.4 kg); 2.8 gal ethanol/bu
# (University of Nebraska dry-mill estimate; RunDaycent.Rmd also used 2.86 in
# MJpkgcorn); 76,330 Btu/gal (lower heating value); 947.817 Btu/MJ.
#
# Reads outputs/summary/daycent_annual_summary.csv.
# Writes outputs/summary/default_results_summary.csv.
#
# Usage: Rscript analysis/summarize_default_results.R

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

repo_root <- normalizePath(file.path(get_script_dir(), ".."), winslash = "/", mustWork = TRUE)
suppressPackageStartupMessages(library(data.table))

start_year <- 2020L
horizon <- 30L
c_to_co2 <- 44 / 12
grain_c_fraction <- 0.435
dry_kg_per_bushel <- 56 * 0.45359237 * (1 - 0.155)
gal_ethanol_per_bushel <- 2.8
btu_per_gal <- 76330
btu_per_mj <- 947.817
mj_per_bushel <- gal_ethanol_per_bushel * btu_per_gal / btu_per_mj
bu_per_ha_to_bu_per_ac <- 1 / 2.471054

practices <- data.table(
  practice = c("conv", "nt", "rt", "cc"),
  practice_label = c("Conventional", "No-till", "Reduced till", "Cover crop (cereal rye)")
)
practices[, scenario_id := paste0(practice, "_n_obs_hlu_site_cont_w_obs")]

annual <- fread(file.path(repo_root, "outputs", "summary", "daycent_annual_summary.csv"))
annual <- annual[scenario_id %in% practices$scenario_id]
stocks <- annual[year %in% c(start_year, start_year + horizon),
                 .(somsc_2020_mg_c_ha = somsc_mg_c_ha[year == start_year],
                   somsc_2050_mg_c_ha = somsc_mg_c_ha[year == start_year + horizon]), by = scenario_id]
grain <- annual[year >= start_year & year < start_year + horizon,
                .(corn_grain_c_g_m2 = sum(annual_cgrain), harvest_years = sum(annual_cgrain > 0)), by = scenario_id]
out <- practices[stocks, on = "scenario_id"][grain, on = "scenario_id"]
if (nrow(out) != 4L || any(out$harvest_years != horizon)) stop("Missing default scenario data.", call. = FALSE)

out[, `:=`(
  soc_change_mg_c_ha = somsc_2050_mg_c_ha - somsc_2020_mg_c_ha,
  corn_dry_grain_mg_ha_30yr = corn_grain_c_g_m2 * 10 / grain_c_fraction / 1000,
  corn_bu_ha_30yr = corn_grain_c_g_m2 * 10 / grain_c_fraction / dry_kg_per_bushel
)]
out[, `:=`(corn_bu_ac_yr = corn_bu_ha_30yr / horizon * bu_per_ha_to_bu_per_ac,
           ethanol_mj_ha_30yr = corn_bu_ha_30yr * mj_per_bushel)]
conv_change <- out[practice == "conv", soc_change_mg_c_ha]
out[, net_soc_accumulation_mg_c_ha := soc_change_mg_c_ha - conv_change]
out[, `:=`(
  net_soc_accumulation_mg_co2e_ha = net_soc_accumulation_mg_c_ha * c_to_co2,
  avg_net_soc_gain_mg_c_ha_yr = net_soc_accumulation_mg_c_ha / horizon,
  avg_net_soc_gain_mg_co2e_ha_yr = net_soc_accumulation_mg_c_ha * c_to_co2 / horizon,
  net_soc_per_bushel_kg_c_bu = 1000 * net_soc_accumulation_mg_c_ha / corn_bu_ha_30yr,
  net_soc_per_bushel_kg_co2e_bu = 1000 * net_soc_accumulation_mg_c_ha * c_to_co2 / corn_bu_ha_30yr,
  net_soc_per_mj_ethanol_g_c_mj = 1e6 * net_soc_accumulation_mg_c_ha / ethanol_mj_ha_30yr,
  net_soc_per_mj_ethanol_g_co2e_mj = 1e6 * net_soc_accumulation_mg_c_ha * c_to_co2 / ethanol_mj_ha_30yr
)]

summary <- out[match(practices$practice, practice), .(
  practice, practice_label,
  somsc_2020_mg_c_ha, somsc_2050_mg_c_ha, soc_change_mg_c_ha,
  net_soc_accumulation_mg_c_ha, net_soc_accumulation_mg_co2e_ha,
  avg_net_soc_gain_mg_c_ha_yr, avg_net_soc_gain_mg_co2e_ha_yr,
  corn_bu_ha_30yr, corn_bu_ac_yr, ethanol_mj_ha_30yr,
  net_soc_per_bushel_kg_c_bu, net_soc_per_bushel_kg_co2e_bu,
  net_soc_per_mj_ethanol_g_c_mj, net_soc_per_mj_ethanol_g_co2e_mj
)]
num <- names(summary)[vapply(summary, is.numeric, logical(1))]
summary[, (num) := lapply(.SD, signif, digits = 5), .SDcols = num]
summary[, `:=`(
  reference = "Continuous conventional, same N rate (UAN20) and history",
  carbon_pool = "somsc (0-20 cm)", period = "2020-2050 (30 yr); harvests 2020-2049",
  conversions = sprintf("%.3f g C/g grain; %.2f kg dry grain/bu (56 lb at 15.5%% moisture); %.1f gal/bu; %.0f Btu/gal; %.1f MJ/bu",
                        grain_c_fraction, dry_kg_per_bushel, gal_ethanol_per_bushel, btu_per_gal, mj_per_bushel)
)]
path <- file.path(repo_root, "outputs", "summary", "default_results_summary.csv")
fwrite(summary, path)
options(width = 200)
print(summary[, .(practice, net_soc_accumulation_mg_c_ha, avg_net_soc_gain_mg_c_ha_yr, avg_net_soc_gain_mg_co2e_ha_yr,
                  corn_bu_ac_yr, net_soc_per_bushel_kg_c_bu, net_soc_per_mj_ethanol_g_co2e_mj)])
message("Wrote ", path)
