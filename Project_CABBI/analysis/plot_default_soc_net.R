# Default scenarios, 2020-2050: somsc stocks (left) and net SOC of each
# conservation practice relative to conventional (right).
#
# Default scenarios: observed N rate (UAN20), site-specific history,
# continuous management, observed weather. Net SOC in year t = practice somsc
# minus conventional somsc at the start of year t (the default conventional, cf_conv); both
# start from the same 2020 stock, so it is the cumulative credit basis
# (credit over horizon h = net SOC in 2020 + h, divided by h, times 44/12).
#
# Reads outputs/summary/daycent_annual_summary.csv (start-of-year snapshots).
# Writes outputs/summary/default_soc_and_net_soc.png and .csv.
#
# Usage: Rscript analysis/plot_default_soc_net.R

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
suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
})

practices <- data.table(
  practice = c("conv", "nt", "rt", "cc"),
  label = c("Conventional", "No-till", "Reduced till", "Cover crop"),
  color = c("#52514e", "#2a78d6", "#1f9e74", "#c7743a"),
  linetype = c("solid", "longdash", "dotdash", "dotted")
)
practices[, scenario_id := paste0(practice, "_n_obs_hlu_site_cont_w_obs")]

annual <- fread(file.path(repo_root, "outputs", "summary", "daycent_annual_summary.csv"))
soc <- annual[scenario_id %in% practices$scenario_id & year >= 2020 & year <= 2050,
              .(scenario_id, year, somsc = somsc_mg_c_ha)]
soc <- practices[, .(scenario_id, practice, label)][soc, on = "scenario_id"]
conv <- soc[practice == "conv", .(year, conv_somsc = somsc)]
soc <- conv[soc, on = "year"]
soc[, net_soc := somsc - conv_somsc]
fwrite(soc[, .(practice, label, year, somsc_mg_c_ha = somsc, net_soc_mg_c_ha = net_soc)],
       file.path(repo_root, "outputs", "summary", "default_soc_and_net_soc.csv"))

# Panel names double as the y-axis titles (strips placed outside on the left).
panel_names <- c("SOC (Mg C/ha)", "Net SOC vs conventional (Mg C/ha)")
plot_data <- rbind(
  soc[, .(panel = panel_names[1], label, year, value = somsc)],
  soc[practice != "conv", .(panel = panel_names[2], label, year, value = net_soc)]
)
plot_data[, panel := factor(panel, levels = panel_names)]
plot_data[, label := factor(label, levels = practices$label)]
end_net <- soc[practice != "conv" & year == 2050, .(label = factor(label, levels = practices$label), net_soc)]
zero_line <- data.table(panel = factor(panel_names[2], levels = panel_names), y = 0)

p <- ggplot(plot_data, aes(year, value, color = label, linetype = label)) +
  geom_hline(data = zero_line, aes(yintercept = y), color = "#b5b4ae", linewidth = 0.4) +
  geom_line(linewidth = 0.8) +
  geom_text(data = end_net[, .(panel = factor(panel_names[2], levels = panel_names), label, year = 2050, value = net_soc)],
            aes(label = sprintf("%+.1f", value)), hjust = -0.2, size = 3.2, show.legend = FALSE) +
  facet_wrap(~ panel, scales = "free_y", strip.position = "left") +
  scale_color_manual(values = setNames(practices$color, practices$label)) +
  scale_linetype_manual(values = setNames(practices$linetype, practices$label)) +
  scale_x_continuous(breaks = seq(2020, 2050, 10), limits = c(2020, 2053)) +
  labs(x = NULL, y = NULL, color = NULL, linetype = NULL,
       title = "Default scenarios at the Energy Farm (DayCent-CABBI), 2020-2050",
       subtitle = "UAN20 (202 kg N/ha), site-specific history, continuous management, observed weather (2008-2020 cycled)",
       caption = paste("SOC: start-of-year somsc, 0-20 cm. Net SOC = practice minus conventional in the same year",
                       "(default conventional: spring field cultivator + fall field cultivator and tandem disk);\nlabels give 2050 values.",
                       "30-yr credit = 2050 net SOC / 30 x 44/12.")) +
  theme_minimal() +
  theme(legend.position = "top", panel.grid.minor = element_blank(),
        strip.placement = "outside", strip.text.y.left = element_text(size = 11, angle = 90),
        panel.spacing = unit(2.5, "lines"))
ggsave(file.path(repo_root, "outputs", "summary", "default_soc_and_net_soc.png"), p,
       width = 11, height = 5, dpi = 150)

# Publication version: 6.5 in wide (a letter page with 1 in margins), every text
# element at least 11 pt at that size, panel titles on top with one shared unit
# axis, and no title, subtitle, or caption (those go in the manuscript caption).
pub_panels <- c("SOC", "Net SOC vs. conventional")
pub_data <- copy(plot_data)[, panel := factor(pub_panels[as.integer(panel)], levels = pub_panels)]
pub_end <- end_net[, .(panel = factor(pub_panels[2], levels = pub_panels), label, year = 2050, value = net_soc)]
p_pub <- ggplot(pub_data, aes(year, value, color = label, linetype = label)) +
  geom_hline(data = data.table(panel = factor(pub_panels[2], levels = pub_panels), y = 0),
             aes(yintercept = y), color = "#b5b4ae", linewidth = 0.4) +
  geom_line(linewidth = 0.9) +
  geom_text(data = pub_end, aes(label = sprintf("%+.1f", value)), hjust = -0.15, size = 11 / .pt,
            show.legend = FALSE) +
  facet_wrap(~ panel, scales = "free_y") +
  scale_color_manual(values = setNames(practices$color, practices$label)) +
  scale_linetype_manual(values = setNames(practices$linetype, practices$label)) +
  scale_x_continuous(breaks = seq(2020, 2050, 10), limits = c(2020, 2057)) +
  labs(x = NULL, y = expression(Mg~C~ha^-1), color = NULL, linetype = NULL) +
  theme_minimal(base_size = 11) +
  theme(text = element_text(size = 11, color = "#0b0b0b"),
        axis.text = element_text(size = 11, color = "#3d3c39"),
        axis.title.y = element_text(size = 12),
        strip.text = element_text(size = 12, face = "bold", hjust = 0),
        legend.text = element_text(size = 11), legend.position = "top",
        legend.key.width = unit(26, "pt"), legend.margin = margin(0, 0, 0, 0),
        panel.grid.minor = element_blank(), panel.spacing.x = unit(14, "pt"),
        plot.margin = margin(4, 6, 4, 4))
pub_path <- file.path(repo_root, "outputs", "summary", "default_soc_and_net_soc_pub")
ggsave(paste0(pub_path, ".png"), p_pub, width = 6.5, height = 3.8, dpi = 600, bg = "white")
ggsave(paste0(pub_path, ".pdf"), p_pub, width = 6.5, height = 3.8, bg = "white")
print(end_net)
