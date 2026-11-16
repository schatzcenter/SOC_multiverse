# Empirical net SOC rate vs study duration (as in plot_duration_scatter.R),
# with the spread of the DayCent scenario matrix around the default model.
#
# At each horizon h = 1-30 years since 2020, the annualized net credit of every
# model specification in the sensitivity set (Project_CABBI
# credit_horizon_functions.R; same definitions as calculate_credit_values.R):
#   - model inputs (farm + model): N rate (UAN10/20/30), 4 land-use histories,
#     cycling (continuous, every 5 or 10 years), DEC4 (0.0022/0.0025/0.0048);
#     108 scenarios per practice;
#   - accounting decisions: counterfactual (3 conventional definitions),
#     carbon pool (somsc, slow + passive, somtc, totc, totsysc), N2O (none, direct
#     AR5), functional unit (area, bushel); 60 protocols.
# Bands are the 2.5th-97.5th percentiles across equally weighted
# specifications (the central 95% of the ensemble, not a statistical
# confidence interval):
#   - combined: all 108 x 60 = 6,480 specifications;
#   - model inputs: the 108 scenarios under the reference protocol
#     (default conventional, somsc, SOC only, per area);
#   - accounting: the 60 protocols for the default farm (UAN20, site history,
#     continuous, default DEC4).
# Credits that include N2O are in CO2e; all are shown in Mg C-equivalent
# (CO2e x 12/44) to share the axis with the empirical SOC rates.
#
# With --soc-only, the N2O option is held at "SOC only" (30 accounting
# protocols, 3,240 combined specifications) and the outputs get a _soc_only
# suffix.
#
# Writes duration_vs_net_soc_band_combined[_soc_only].png,
# duration_vs_net_soc_band_split[_soc_only].png, and
# model_band_by_horizon[_soc_only].csv.
#
# With --median-line, the red line is the median of the combined ensemble at
# each horizon instead of the default run (suffix _median_line; both figures).
#
# Usage: Rscript plot_duration_model_bands.R [--soc-only] [--median-line]   (from the MetaAnalysis folder)

suppressPackageStartupMessages({
  library(data.table)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
})

get_script_dir <- function() {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(file_arg) > 0) return(dirname(normalizePath(sub("^--file=", "", file_arg[1]))))
  getwd()
}
setwd(get_script_dir())

cabbi_root <- normalizePath(file.path("..", "Project_CABBI"), winslash = "/")
source(file.path(cabbi_root, "analysis", "credit_horizon_functions.R"))

practice_labels <- c(NT = "No-till", RT = "Reduced-till", CC = "Cover crop")
method_labels <- c(rate_fd = "Measured: fixed depth (0-20 cm)", rate_esm = "Measured: equivalent soil mass")
co2e_to_c <- 12 / 44
soc_only <- "--soc-only" %in% commandArgs(trailingOnly = TRUE)
n2o_options <- if (soc_only) "none" else c("none", "direct_ar5")
median_line <- "--median-line" %in% commandArgs(trailingOnly = TRUE)
suffix <- paste0(if (soc_only) "_soc_only" else "", if (median_line) "_median_line" else "")
n_protocols <- 3L * 5L * length(n2o_options) * 2L
n_combined <- format(108L * n_protocols, big.mark = ",")

# Model ensemble ----------------------------------------------------------------
credits <- horizon_credits(cabbi_root, horizons = 1:30,
                           pools = c("somsc", "slow_passive", "somtc", "totc", "totsysc"),
                           counterfactuals = c("cf_conv", "cf_convplow", "cf_convrt"),
                           n2o_options = n2o_options, units = c("area", "bushel"))
credits[, `:=`(Change = factor(toupper(conservation_practice), levels = names(practice_labels)),
               rate = net_annual * co2e_to_c)]
credits[, `:=`(default_farm = n_rate == "n_obs" & historic_land_use == "hlu_site" &
                 cycling_frequency == "cont" & dec4 == "dec4_def",
               reference_protocol = counterfactual == "cf_conv" & carbon_pool == "somsc" &
                 n2o_option == "none" & functional_unit == "area")]

spec_counts <- credits[h == 30, .(farm = uniqueN(scenario_id),
                                  protocols = uniqueN(paste(counterfactual, carbon_pool, n2o_option, functional_unit))),
                       by = Change]
stopifnot(all(spec_counts$farm == 108), all(spec_counts$protocols == n_protocols))

band <- function(d, label) {
  d[, .(lower = quantile(rate, 0.025), median = median(rate), upper = quantile(rate, 0.975), n = .N),
    by = .(Change, years = h)][, source := label][]
}
bands <- rbind(band(credits, "Combined (model inputs + accounting)"),
               band(credits[reference_protocol == TRUE], "Model inputs"),
               band(credits[default_farm == TRUE], "Accounting decisions"))
default_curve <- credits[default_farm & reference_protocol, .(Change, years = h, rate)]
stopifnot(nrow(default_curve) == 90)
fwrite(bands[, .(source, Change, years, n, lower = round(lower, 4), median = round(median, 4), upper = round(upper, 4))],
       paste0("model_band_by_horizon", suffix, ".csv"))

# Empirical studies and FD-CIC --------------------------------------------------
# DATA NOT INCLUDED: the Global Soil Carbon Fractions: Regenerative + Conventional Croplands
# dataset is not redistributed in this repository. It is available through LandEngine
# (https://landengine.org/). Citation: A. M. Prairie, A. E. King, and M. F. Cotrufo, "Restoring
# particulate and mineral-associated organic carbon through regenerative agriculture," Proc. Natl.
# Acad. Sci., vol. 120, no. 21, p. e2217481120, May 2023, doi: 10.1073/pnas.2217481120.
# empirical_soc_study_means.csv is written by SOCMetaAnalysis.Rmd from that dataset.
study <- read.csv("empirical_soc_study_means.csv") %>%
  pivot_longer(c(rate_fd, rate_esm), names_to = "method", values_to = "rate") %>%
  filter(!is.na(rate)) %>%
  mutate(Change = factor(Change, levels = names(practice_labels)),
         method = factor(method_labels[method], levels = method_labels))
fdcic_label <- "FD-CIC 2026 (Champaign, IL)"
# 2026 FD-CIC soil carbon for Champaign, IL: reported as emissions (a net sink is
# negative), so the sign is flipped to match this analysis (sink = positive).
fdcic_2026 <- read.csv("20206FDCIC_ChIL.csv", check.names = FALSE)
names(fdcic_2026)[1] <- "Mgmt"
fdcic_2026 <- fdcic_2026 %>%
  filter(type == "soil carbon emissions/removals", Mgmt %in% names(practice_labels)) %>%
  transmute(Change = factor(Mgmt, levels = names(practice_labels)),
            rate = -suppressWarnings(as.numeric(MgC_hayr)), series = fdcic_label)
fdcic <- fdcic_2026

# Figures -------------------------------------------------------------------------
combined <- bands[source == "Combined (model inputs + accounting)"]
# Red line: the default run, or (--median-line) the median of the combined
# ensemble at each horizon.
model_line <- if (median_line) combined[, .(Change, years, rate = median)] else default_curve
line_label <- if (median_line) "DayCent ensemble median" else "Model: Reference specifications Energy Farm"
line_colors <- setNames(c("#d03b3b", "#6a4c9c"), c(line_label, fdcic_label))
y_label <- if (soc_only) {
  expression(Annualized~net~SOC~(Mg~C~ha^-1~yr^-1))
} else {
  expression(Annualized~net~SOC~or~credit~(Mg~C[eq]~ha^-1~yr^-1))
}
caption_base <- paste(
  "Points: study-level empirical net SOC (practice minus conventional, divided by years since adoption).",
  if (median_line) {
    "Red: median of all model specifications (model inputs x accounting decisions) at each horizon (equal weight); dot = 30 years."
  } else {
    "Red: default DayCent model (UAN20, site history, continuous; somsc vs default conventional, SOC only, per area); dot = 30 years."
  },
  paste("Purple dotted: FD-CIC 2026 soil C (Champaign, IL; sign flipped so a sink is positive).",
        "FD-CIC values have no duration."),
  paste("Bands: 2.5th-97.5th percentile of equally weighted model specifications at each horizon",
        if (soc_only) {
          "(central 95% of the ensemble, not a statistical confidence interval);\nN2O held at SOC only (no N2O) in every band."
        } else {
          "(central 95% of the ensemble, not a statistical confidence interval);\ncredits with N2O converted from CO2e x 12/44."
        }),
  sep = "\n")
accounting_dims <- if (soc_only) "counterfactual, carbon pool, functional unit" else "counterfactual, carbon pool, N2O, functional unit"

base_layers <- function(p) {
  p +
    geom_hline(yintercept = 0, color = "#b5b4ae") +
    geom_hline(data = fdcic, aes(yintercept = rate, color = series),
               linetype = "dotted", linewidth = 1) +
    geom_line(data = model_line, aes(x = years, y = rate, color = line_label), linewidth = 1) +
    geom_point(data = model_line[years == 30], aes(x = years, y = rate, color = line_label), size = 2.5) +
    geom_point(data = study, aes(x = duration, y = rate, shape = method), color = "#3d3c39", size = 2.2, stroke = 0.8) +
    facet_wrap(~Change, labeller = labeller(Change = practice_labels)) +
    scale_shape_manual(name = NULL, values = setNames(c(16, 1), method_labels)) +
    scale_color_manual(name = NULL, values = line_colors, breaks = names(line_colors)) +
    guides(color = guide_legend(override.aes = list(linetype = c("solid", "dotted"), shape = c(16, NA)),
                                order = 2),
           shape = guide_legend(order = 1), fill = guide_legend(order = 3)) +
    labs(x = "Study duration / years since adoption (model: years since 2020)", y = y_label) +
    theme_minimal(base_size = 11) +
    theme(legend.position = "bottom", legend.box = "vertical", panel.grid.minor = element_blank(),
          legend.spacing.y = unit(0, "pt"), legend.margin = margin(0, 0, 0, 0),
          legend.box.spacing = unit(4, "pt"),
          plot.caption = element_text(hjust = 0, color = "#6b6a66", size = 8.5))
}

p_combined <- ggplot() +
  geom_ribbon(data = combined, aes(x = years, ymin = lower, ymax = upper,
                                   fill = "Model inputs + accounting decisions (central 95%)"), alpha = 0.22) +
  scale_fill_manual(name = NULL, values = c("Model inputs + accounting decisions (central 95%)" = "#d03b3b"))
p_combined <- base_layers(p_combined) +
  labs(title = "Empirical net SOC vs study duration, with the full DayCent scenario matrix",
       caption = paste0(caption_base, "\nBand: all ", n_combined, " specifications per practice (108 farm/model scenarios x ",
                        n_protocols, " accounting protocols: ", accounting_dims, ")."))
ggsave(paste0("duration_vs_net_soc_band_combined", suffix, ".png"), p_combined, width = 11, height = 5.9, dpi = 200, bg = "white")

split_fill <- c("Model inputs (central 95%)" = "#1baf7a", "Accounting decisions (central 95%)" = "#eda100")
split <- bands[source != "Combined (model inputs + accounting)"]
split[, band := factor(ifelse(source == "Model inputs", names(split_fill)[1], names(split_fill)[2]), levels = names(split_fill))]
p_split <- ggplot() +
  geom_ribbon(data = split, aes(x = years, ymin = lower, ymax = upper, fill = band), alpha = 0.28) +
  scale_fill_manual(name = NULL, values = split_fill)
p_split <- base_layers(p_split) +
  labs(title = "Empirical net SOC vs study duration: model-input and accounting-decision spread",
       caption = paste0(caption_base, "\nGreen: 108 farm/model scenarios (N rate, land-use history, cycling, DEC4) under the reference protocol. ",
                        "Amber: ", n_protocols, " accounting protocols\n(", accounting_dims,
                        ") for the default farm. Overlap appears as the blend of both."))
ggsave(paste0("duration_vs_net_soc_band_split", suffix, ".png"), p_split, width = 11, height = 5.9, dpi = 200, bg = "white")

# Publication version of the split figure: 6.5 in wide (a letter page with 1 in
# margins), every text element at least 11 pt at that size, and no title or
# caption (those go in the manuscript's figure caption).
p_split_pub <- p_split +
  labs(title = NULL, caption = NULL, x = "Years since adoption (studies) or since 2020 (model)") +
  theme(text = element_text(size = 11, color = "#0b0b0b"),
        axis.text = element_text(size = 11, color = "#3d3c39"),
        axis.title = element_text(size = 12),
        strip.text = element_text(size = 12, face = "bold"),
        legend.text = element_text(size = 11),
        legend.key.width = unit(22, "pt"),
        panel.spacing.x = unit(12, "pt"),
        plot.margin = margin(6, 8, 4, 4))
pub_path <- paste0("duration_vs_net_soc_band_split", suffix, "_pub")
ggsave(paste0(pub_path, ".png"), p_split_pub, width = 6.5, height = 5.2, dpi = 600, bg = "white")
ggsave(paste0(pub_path, ".pdf"), p_split_pub, width = 6.5, height = 5.2, bg = "white")

print(bands[years %in% c(5, 10, 20, 30), .(source, Change, years, lower = round(lower, 3), upper = round(upper, 3))][order(Change, years, source)])
message("Wrote duration_vs_net_soc_band_combined", suffix, ".png, duration_vs_net_soc_band_split", suffix,
        ".png, model_band_by_horizon", suffix, ".csv")
