# Distribution of the annualized net credit across every specification in the
# sensitivity set (19,440 per practice: 108 farm-model scenarios x 180
# accounting protocols), one panel per conservation practice on a shared x axis.
#
# Histogram of all specifications (equal weight), shaded central 95%
# (2.5th-97.5th percentile), ensemble median (dashed), default specification
# (dotted), and zero. Per-bushel credits are on their per-area scale, as in
# plot_tornado.R.
#
# Reads outputs/summary/accounting_results.csv.
# Writes outputs/summary/ensemble_distribution_pub.png/.pdf and
# ensemble_distribution_summary.csv.
#
# Usage: Rscript analysis/plot_ensemble_distribution.R

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
output_dir <- file.path(repo_root, "outputs", "summary")
suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
})

# Default specification (as in plot_tornado.R)
defaults <- list(n_rate = "n_obs", historic_land_use = "hlu_site", cycling_frequency = "cont", dec4 = "dec4_def",
                 carbon_pool = "somsc", horizon_years = 30L, counterfactual = "cf_conv", n2o_option = "none",
                 functional_unit = "area")
practices <- c(nt = "No-till", rt = "Reduced-till", cc = "Cover crop")

results <- fread(file.path(output_dir, "accounting_results.csv"))
results[, practice := factor(practices[conservation_practice], levels = practices)]
at_default <- results
for (v in names(defaults)) at_default <- at_default[get(v) == defaults[[v]]]
stopifnot(nrow(at_default) == length(practices))

summary_stats <- results[, .(specifications = .N, mean = mean(net_credit_mg_co2e_ha_yr),
                             sd = sd(net_credit_mg_co2e_ha_yr), median = median(net_credit_mg_co2e_ha_yr),
                             q025 = quantile(net_credit_mg_co2e_ha_yr, 0.025, names = FALSE),
                             q975 = quantile(net_credit_mg_co2e_ha_yr, 0.975, names = FALSE),
                             min = min(net_credit_mg_co2e_ha_yr), max = max(net_credit_mg_co2e_ha_yr),
                             share_negative = mean(net_credit_mg_co2e_ha_yr < 0)),
                         by = .(conservation_practice, practice)]
summary_stats[at_default, on = "conservation_practice", default := i.net_credit_mg_co2e_ha_yr]
fwrite(summary_stats, file.path(output_dir, "ensemble_distribution_summary.csv"))

lines <- rbind(summary_stats[, .(practice, x = median, line = "Ensemble median")],
               summary_stats[, .(practice, x = default, line = "Default specification")])
labels <- summary_stats[, .(practice, label = sprintf("Median %.2f  |  central 95%% %.2f to %.2f  |  %.0f%% below zero",
                                                     median, q025, q975, 100 * share_negative))]

text_pt <- 8
p <- ggplot(results, aes(x = net_credit_mg_co2e_ha_yr)) +
  geom_rect(data = summary_stats, aes(xmin = q025, xmax = q975, ymin = -Inf, ymax = Inf, fill = "Central 95%"),
            inherit.aes = FALSE) +
  geom_histogram(binwidth = 0.1, boundary = 0, fill = "#52514e", color = NA) +
  geom_vline(xintercept = 0, color = "#b5b4ae", linewidth = 0.4) +
  geom_vline(data = lines, aes(xintercept = x, linetype = line, color = line), linewidth = 0.6) +
  geom_text(data = labels, aes(x = Inf, y = Inf, label = label), hjust = 1.02, vjust = 1.5, size = text_pt / .pt,
            color = "#0b0b0b") +
  facet_wrap(~practice, ncol = 1, strip.position = "top") +
  scale_x_continuous(breaks = seq(-2, 10, 1)) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.18))) +
  scale_fill_manual(values = c("Central 95%" = "#ececea"), name = NULL) +
  scale_linetype_manual(values = c("Ensemble median" = "dashed", "Default specification" = "dotted"), name = NULL) +
  scale_color_manual(values = c("Ensemble median" = "#d03b3b", "Default specification" = "#0b0b0b"), name = NULL) +
  labs(x = expression(Annualized~net~benefit~(t~CO[2]*e~ha^-1~yr^-1)), y = "Specifications") +
  theme_minimal(base_size = text_pt) +
  theme(text = element_text(size = text_pt, color = "#0b0b0b"),
        axis.text = element_text(size = text_pt, color = "#0b0b0b"),
        axis.title = element_text(size = text_pt + 1),
        strip.text = element_text(size = text_pt + 1, face = "bold", hjust = 0),
        legend.position = "bottom", legend.text = element_text(size = text_pt),
        legend.key.width = unit(22, "pt"), legend.margin = margin(0, 0, 0, 0),
        panel.grid.minor = element_blank(), panel.grid.major.x = element_line(color = "#f3f3f1"),
        panel.spacing.y = unit(8, "pt"), plot.margin = margin(4, 6, 4, 4))

out_path <- file.path(output_dir, "ensemble_distribution_pub")
ggsave(paste0(out_path, ".png"), p, width = 6.5, height = 5, dpi = 600, bg = "white")
ggsave(paste0(out_path, ".pdf"), p, width = 6.5, height = 5, bg = "white")
message("Wrote ", out_path, ".png/.pdf and ensemble_distribution_summary.csv")
