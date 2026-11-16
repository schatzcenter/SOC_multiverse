# Tornado charts of annualized net credit for each conservation practice.
#
# One-at-a-time: each bar spans the change in net credit (t CO2e/ha/yr) when one
# variable or accounting decision is swept across all of its levels while every
# other one stays at the default below. The time horizon is not swept (held at
# 30 years).
#
# Full sensitivity: each bar spans the variable's level means, where each level
# mean averages net credit over every combination of all other variables and
# decisions (each enumerated specification weighted equally). The whisker spans
# the 5th percentile of the effect at the lowest-mean level to the 95th
# percentile at the highest-mean level, where an effect is the credit minus the
# mean over that variable's levels for the same combination of other choices;
# a whisker much wider than its bar indicates strong interactions.
#
# The functional unit is swept like the other decisions using its per-area
# value (for per-bushel crediting, credit per bushel x project bushels/ha/yr).
#
# Both sets are drawn relative to the default scenario's net credit (0 line)
# and include the USDA FD-CIC 2026 soil carbon value for each practice (except
# the full-sensitivity charts centred on the ensemble mean). Values come from outputs/summary/accounting_results.csv.

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
output_dir <- file.path(repo_root, "outputs", "summary")
results_path <- file.path(output_dir, "accounting_results.csv")
if (!file.exists(results_path)) {
  stop("Missing ", results_path, "; run calculate_credit_values.R first.", call. = FALSE)
}

# Default scenario: the 0 line in every panel.
defaults <- list(
  n_rate = "n_obs",
  historic_land_use = "hlu_site",
  cycling_frequency = "cont",
  dec4 = "dec4_def",
  carbon_pool = "somsc",
  horizon_years = 30L,
  counterfactual = "cf_conv",
  n2o_option = "none",
  functional_unit = "area"
)
variable_labels <- c(
  n_rate = "N rate",
  historic_land_use = "Land-use history",
  cycling_frequency = "Cycling",
  dec4 = "DEC4 (model)",
  carbon_pool = "Carbon pool",
  horizon_years = "Horizon",
  counterfactual = "Counterfactual",
  n2o_option = "N2O treatment",
  functional_unit = "Functional unit"
)
variable_groups <- c(
  n_rate = "biophysical", historic_land_use = "biophysical",
  cycling_frequency = "biophysical", dec4 = "biophysical", carbon_pool = "accounting",
  horizon_years = "accounting", counterfactual = "accounting", n2o_option = "accounting",
  functional_unit = "accounting"
)
level_labels <- c(
  n_none = "0 N", uan3 = "UAN3", uan6 = "UAN6", uan8 = "UAN8", uan10 = "UAN10", uan11 = "UAN11",
  uan18 = "UAN18", n_obs = "UAN20", uan30 = "UAN30",
  dec4_lo = "DEC4 0.0022", dec4_def = "DEC4 default (0.0025)", dec4_hi = "DEC4 0.0048",
  hlu_site = "Site history", hlu_cs = "Corn-soy", hlu_cc = "Cont. corn",
  hlu_ntc = "No-till corn", hlu_cs0n = "Corn-soy, 0 N",
  cont = "Continuous", rev2 = "Cycle 2 yr", rev3 = "Cycle 3 yr", rev4 = "Cycle 4 yr",
  rev5 = "Cycle 5 yr", rev6 = "Cycle 6 yr", rev7 = "Cycle 7 yr", rev8 = "Cycle 8 yr",
  rev10 = "Cycle 10 yr", adopt2_rev = "2 yr then revert", adopt5_rev = "5 yr then revert",
  adopt10_rev = "10 yr then revert",
  slow_passive = "Slow+passive", somsc = "somsc", soil_surface = "Soil+surface",
  totc = "totc", somtc = "somtc",
  totsysc = "totsysc",
  "2" = "2 yr", "5" = "5 yr", "10" = "10 yr", "20" = "20 yr", "30" = "30 yr",
  cf_conv = "Conv.: fall cultivator/disk", cf_convplow = "Conv.: plow", cf_convrt = "Conv. = RT",
  none = "SOC only", direct_ar5 = "Direct N2O, GWP 265",
  area = "Per area", bushel = "Per bushel (CI)"
)
practices <- c(nt = "No-till", rt = "Reduced-till", cc = "Cover crop")

# Sensitivity-set scenarios only (set-aside runs are excluded).
results <- fread(results_path)
results <- results[analysis_set == "sensitivity"]
variables <- names(defaults)

# One-at-a-time sweeps -----------------------------------------------------------
# The horizon is held at its default (30 years) and not swept.
swept_variables <- setdiff(variables, "horizon_years")

sweeps <- rbindlist(lapply(names(practices), function(practice) {
  practice_rows <- results[conservation_practice == practice]
  at_default <- practice_rows
  for (v in variables) {
    at_default <- at_default[get(v) == defaults[[v]]]
  }
  if (nrow(at_default) != 1L) {
    stop("Expected one default row for ", practice, " but found ", nrow(at_default), call. = FALSE)
  }
  default_value <- at_default$net_credit_mg_co2e_ha_yr

  rbindlist(lapply(swept_variables, function(swept) {
    rows <- practice_rows
    for (v in setdiff(variables, swept)) {
      rows <- rows[get(v) == defaults[[v]]]
    }
    data.table(
      conservation_practice = practice,
      variable = swept,
      level = as.character(rows[[swept]]),
      is_default = as.character(rows[[swept]]) == as.character(defaults[[swept]]),
      net_credit_mg_co2e_ha_yr = rows$net_credit_mg_co2e_ha_yr,
      default_net_credit_mg_co2e_ha_yr = default_value,
      change_mg_co2e_ha_yr = rows$net_credit_mg_co2e_ha_yr - default_value
    )
  }))
}))
sweeps[, level_label := level_labels[level]]
sweeps[, variable_label := variable_labels[variable]]
sweeps[, group := variable_groups[variable]]
sweeps[, change_pct := 100 * change_mg_co2e_ha_yr / default_net_credit_mg_co2e_ha_yr]
sweep_path <- file.path(output_dir, "tornado_net_credit.csv")
fwrite(sweeps, sweep_path)

default_values <- unique(sweeps[, .(conservation_practice, default = default_net_credit_mg_co2e_ha_yr)])

# FD-CIC soil carbon values (USDA Feedstock Carbon Intensity Calculator) ----
# FD-CIC 2026 soil carbon values for Champaign, IL
#   (../MetaAnalysis/20206FDCIC_ChIL.csv). The calculator reports soil carbon
#   as emissions, so a net sink is negative; the sign is flipped here so a
#   sink is a positive credit, as in this analysis. Values per bushel were
#   converted to per hectare in that file with this project's modeled yields.

fdcic_2026_path <- file.path(repo_root, "..", "MetaAnalysis", "20206FDCIC_ChIL.csv")
fdcic_parts <- list()
if (file.exists(fdcic_2026_path)) {
  f26 <- fread(fdcic_2026_path)
  setnames(f26, 1, "Mgmt")
  fdcic_parts$y2026 <- f26[type == "soil carbon emissions/removals" & Mgmt %in% c("NT", "RT", "CC"),
                           .(conservation_practice = tolower(Mgmt), year = 2026L,
                             fdcic = -suppressWarnings(as.numeric(MgCO2_hayr)))]
} else {
  message("FD-CIC 2026 file not found: ", fdcic_2026_path)
}
fdcic <- if (length(fdcic_parts) > 0) {
  f <- rbindlist(fdcic_parts)[default_values, on = "conservation_practice", nomatch = 0L]
  f[, `:=`(change_mg_co2e_ha_yr = fdcic - default, change_pct = 100 * (fdcic - default) / default)]
} else {
  message("No FD-CIC files found; tornado charts drawn without them.")
  NULL
}
fdcic_styles <- data.table(year = 2026L, pch = 24, color = "#2a78d6", label_pos = 3,
                           legend = "FD-CIC 2026 soil C (Champaign, IL)")

# Full sensitivity over the specification ensemble ------------------------------

full <- rbindlist(lapply(names(practices), function(practice) {
  practice_rows <- results[conservation_practice == practice]
  grand_mean <- mean(practice_rows$net_credit_mg_co2e_ha_yr)
  default_value <- default_values[conservation_practice == practice, default]
  rbindlist(lapply(variables, function(v) {
    others <- setdiff(variables, v)
    effects <- practice_rows[, .(level = as.character(get(v)),
                                 effect = net_credit_mg_co2e_ha_yr - mean(net_credit_mg_co2e_ha_yr)),
                             by = others]
    effects[, .(level_mean = grand_mean + mean(effect),
                effect_q05 = grand_mean + quantile(effect, 0.05, names = FALSE),
                effect_q95 = grand_mean + quantile(effect, 0.95, names = FALSE),
                specifications = .N), by = level][
      , `:=`(conservation_practice = practice, variable = v, ensemble_mean = grand_mean,
             default_net_credit_mg_co2e_ha_yr = default_value)]
  }))
}))
full[, `:=`(level_label = level_labels[level], variable_label = variable_labels[variable],
            group = variable_groups[variable])]
for (col in c("level_mean", "effect_q05", "effect_q95", "ensemble_mean")) {
  full[, paste0(col, "_change") := get(col) - default_net_credit_mg_co2e_ha_yr]
  full[, paste0(col, "_pct") := 100 * get(paste0(col, "_change")) / default_net_credit_mg_co2e_ha_yr]
}
full_path <- file.path(output_dir, "tornado_full_sensitivity.csv")
fwrite(full, full_path)

# Median-centred full sensitivity: the same construction with medians. An
# effect is the credit minus the median over the variable's levels for the
# same combination of other choices; the bar spans the overall median plus
# each level's median effect, the whisker the 5th-95th percentile of the
# effects at the extreme levels. Values are shown as deviation from the
# overall median of each practice (t CO2e/ha/yr and % of the median).
full_median <- rbindlist(lapply(names(practices), function(practice) {
  practice_rows <- results[conservation_practice == practice]
  grand_median <- median(practice_rows$net_credit_mg_co2e_ha_yr)
  default_value <- default_values[conservation_practice == practice, default]
  rbindlist(lapply(variables, function(v) {
    others <- setdiff(variables, v)
    effects <- practice_rows[, .(level = as.character(get(v)),
                                 effect = net_credit_mg_co2e_ha_yr - median(net_credit_mg_co2e_ha_yr)),
                             by = others]
    effects[, .(level_value = grand_median + median(effect),
                effect_q05 = grand_median + quantile(effect, 0.05, names = FALSE),
                effect_q95 = grand_median + quantile(effect, 0.95, names = FALSE),
                specifications = .N), by = level][
      , `:=`(conservation_practice = practice, variable = v, ensemble_median = grand_median,
             default_net_credit_mg_co2e_ha_yr = default_value)]
  }))
}))
full_median[, `:=`(level_label = level_labels[level], variable_label = variable_labels[variable],
                   group = variable_groups[variable])]
for (col in c("level_value", "effect_q05", "effect_q95", "default_net_credit_mg_co2e_ha_yr")) {
  full_median[, paste0(col, "_vsmed") := get(col) - ensemble_median]
  full_median[, paste0(col, "_vsmedpct") := 100 * (get(col) - ensemble_median) / ensemble_median]
}
median_values <- unique(full_median[, .(conservation_practice, default = ensemble_median,
                                        default_run = default_net_credit_mg_co2e_ha_yr)])
if (!is.null(fdcic)) {
  fdcic[median_values, on = "conservation_practice", `:=`(
    vsmed = fdcic - i.default, vsmedpct = 100 * (fdcic - i.default) / i.default)]
}
full_median_path <- file.path(output_dir, "tornado_full_sensitivity_median.csv")
fwrite(full_median, full_median_path)

# Plot -----------------------------------------------------------------------

group_colors <- c(biophysical = "#2a78d6", accounting = "#eb6834")
axis_ink <- "#52514e"
fdcic_color <- "#0b0b0b"

# ranges: conservation_practice, variable, group, low, high, low_level,
#         high_level, and optionally whisker_low, whisker_high.
# ticks: conservation_practice, variable, value (white tick per level), or NULL
#        for plain bars.
# reference_lines: per-practice x positions drawn as dashed lines.
draw_tornado <- function(ranges, ticks, fdcic_metric, x_label, default_format, title,
                         footnote, plot_path, reference_lines = NULL, reference_label = NULL,
                         header_values = default_values, show_fdcic = TRUE, x_pad = 0.05) {
  ranges[, span := high - low]
  row_order <- ranges[, .(mean_span = mean(span)), by = variable][order(mean_span), variable]
  has_whiskers <- "whisker_low" %in% names(ranges)
  has_fdcic <- show_fdcic && !is.null(fdcic)
  extent <- c(0, ranges$low, ranges$high,
              if (has_whiskers) c(ranges$whisker_low, ranges$whisker_high),
              if (has_fdcic) fdcic[[fdcic_metric]], unlist(reference_lines))
  x_limits <- range(extent, na.rm = TRUE)
  x_limits <- x_limits + c(-1, 1) * diff(x_limits) * x_pad

  png(plot_path, width = 3600, height = 1650, res = 200)
  # Row labels only on the left panel; the panel widths keep the three plot
  # regions equal (18 in device width, ~0.2 in per margin line).
  left_mar <- c(13.0, 0.5, 0.5)
  right_mar <- c(0.5, 0.5, 2.0)
  plot_width <- (3600 / 200 - sum(left_mar + right_mar) * 0.2) / 3
  layout(matrix(1:3, nrow = 1), widths = plot_width + (left_mar + right_mar) * 0.2)
  footnote_lines <- length(strsplit(footnote, "\n", fixed = TRUE)[[1]])
  par(oma = c(max(3.2, 1.4 + 1.1 * footnote_lines), 0, 3.2, 0), mgp = c(2.5, 0.6, 0), las = 1)
  for (k in seq_along(practices)) {
    practice <- names(practices)[k]
    first_panel <- k == 1L
    par(mar = c(5.0, left_mar[k], 5.2, right_mar[k]))
    panel <- ranges[conservation_practice == practice][match(row_order, variable)]
    default_value <- header_values[conservation_practice == practice, default]
    y <- seq_along(row_order) + if (has_fdcic) 1L else 0L
    plot(NA, xlim = x_limits, ylim = c(0.4, max(y) + 0.6), yaxt = "n", bty = "n",
         xlab = x_label, ylab = "", col.axis = axis_ink, col.lab = axis_ink,
         cex.axis = 1.25, cex.lab = 1.25)
    if (first_panel) {
      axis(2, at = y, labels = variable_labels[row_order], tick = FALSE, col.axis = "#0b0b0b",
           cex.axis = 1.35)
    }
    abline(v = pretty(x_limits), col = "#ececea")
    if (has_whiskers) {
      segments(panel$whisker_low, y, panel$whisker_high, y, col = axis_ink, lwd = 1.4)
      segments(c(panel$whisker_low, panel$whisker_high), c(y, y) - 0.12,
               c(panel$whisker_low, panel$whisker_high), c(y, y) + 0.12, col = axis_ink, lwd = 1.4)
    }
    rect(panel$low, y - 0.3, panel$high, y + 0.3,
         col = unname(group_colors[panel$group]), border = NA)
    if (!is.null(ticks)) {
      for (i in seq_along(row_order)) {
        level_points <- ticks[conservation_practice == practice & variable == row_order[i], value]
        segments(level_points, y[i] - 0.3, level_points, y[i] + 0.3, col = "white", lwd = 1.2)
      }
    }
    abline(v = 0, lty = 3, lwd = 1.6, col = "#0b0b0b")
    if (!is.null(reference_lines)) {
      abline(v = reference_lines[[practice]], lty = 2, lwd = 1.2, col = axis_ink)
    }
    label_low <- if (has_whiskers) pmin(panel$low, panel$whisker_low) else panel$low
    label_high <- if (has_whiskers) pmax(panel$high, panel$whisker_high) else panel$high
    text(label_low, y, panel$low_level, pos = 2, cex = 0.85, col = axis_ink, xpd = NA)
    text(label_high, y, panel$high_level, pos = 4, cex = 0.85, col = axis_ink, xpd = NA)
    if (has_fdcic) {
      fd <- fdcic[conservation_practice == practice]
      abline(h = 1.5, col = "#d8d7d2")
      if (first_panel) {
        axis(2, at = 1, labels = "FD-CIC (USDA)", tick = FALSE, col.axis = "#0b0b0b",
             cex.axis = 1.35, font = 2)
      }
      for (j in seq_len(nrow(fd))) {
        st <- fdcic_styles[year == fd$year[j]]
        points(fd[[fdcic_metric]][j], 1, pch = st$pch, bg = st$color, col = st$color, cex = 1.9)
        text(fd[[fdcic_metric]][j], 1, sprintf("%d: %.2f t CO2e/ha/yr", fd$year[j], fd$fdcic[j]),
             pos = st$label_pos, cex = 0.8, col = st$color, offset = 0.9)
      }
    }
    title(main = practices[[practice]], font.main = 2, cex.main = 1.6, line = 2.7)
    mtext(sprintf(default_format, default_value), side = 3, line = 1.0, cex = 1.05,
          col = axis_ink)
  }
  mtext(title, side = 3, outer = TRUE, line = 1.4, cex = 1.15, font = 2)
  mtext(footnote, side = 1, outer = TRUE, line = max(1.0, footnote_lines - 1), cex = 0.75, col = axis_ink)
  par(fig = c(0, 1, 0, 1), oma = c(0, 0, 0, 0), mar = c(0, 0, 0, 0), new = TRUE)
  plot.new()
  legend("topright", legend = c("Biophysical variable", "Accounting decision"),
         fill = unname(group_colors), border = NA, bty = "n", cex = 1.1, inset = c(0.01, 0.04))
  extra <- data.table(label = character(), pch = numeric(), lty = numeric(), color = character())
  if (has_fdcic) {
    st <- fdcic_styles[year %in% unique(fdcic$year)]
    extra <- rbind(extra, data.table(label = st$legend, pch = st$pch, lty = 0, color = st$color))
  }
  if (!is.null(reference_lines)) {
    extra <- rbind(extra, data.table(label = reference_label, pch = NA, lty = 2, color = axis_ink))
  }
  if (has_whiskers) {
    extra <- rbind(extra, data.table(label = "5th-95th percentile of effect", pch = NA, lty = 1, color = axis_ink))
  }
  if (nrow(extra) > 0) {
    legend("topleft", legend = extra$label, pch = extra$pch, lty = extra$lty, pt.bg = extra$color,
           col = extra$color, bty = "n", cex = 1.1, inset = c(0.01, 0.04))
  }
  dev.off()
  message("Wrote tornado figure to ", plot_path)
}

default_text <- paste("Default (dotted line): UAN20, site history, continuous, default DEC4, somsc, 30 years,",
                      "default conventional (spring field cultivator + fall field cultivator and tandem disk), SOC only, per area. Per-bushel credits are shown as",
                      "credit per bushel x project bushels/ha/yr.")

# One-at-a-time ranges from the sweeps.
oat_ranges <- function(metric) {
  r <- sweeps[, .(low = min(get(metric)), high = max(get(metric)),
                  low_level = level_label[which.min(get(metric))],
                  high_level = level_label[which.max(get(metric))]),
              by = .(conservation_practice, variable, group)]
  # A variable that does not move the result gets one label listing its equal levels.
  flat <- sweeps[, .(flat_label = paste(unique(level_label), collapse = " = ")),
                 by = .(conservation_practice, variable)]
  r[flat, on = c("conservation_practice", "variable"), flat_label := i.flat_label]
  r[high - low < 1e-9, `:=`(low_level = "", high_level = paste(flat_label, "(no change)"))]
  r[, flat_label := NULL][]
}

# Full-sensitivity ranges: bar across level means, whisker from the lowest
# level's 5th percentile to the highest level's 95th percentile.
full_ranges <- function(suffix, data = full, level_column = "level_mean") {
  m <- paste0(level_column, "_", suffix)
  q05 <- paste0("effect_q05_", suffix)
  q95 <- paste0("effect_q95_", suffix)
  data[, {
    lo <- which.min(get(m))
    hi <- which.max(get(m))
    # Levels tied at the extreme: label the other level on the high side.
    if (hi == lo && .N > 1L) hi <- setdiff(seq_len(.N), lo)[which.max(get(m)[-lo])]
    .(low = get(m)[lo], high = get(m)[hi], low_level = level_label[lo], high_level = level_label[hi],
      whisker_low = get(q05)[lo], whisker_high = get(q95)[hi])
  }, by = .(conservation_practice, variable, group)]
}

for (unit in c("t", "pct")) {
  oat_metric <- if (unit == "t") "change_mg_co2e_ha_yr" else "change_pct"
  full_suffix <- if (unit == "t") "change" else "pct"
  x_label <- if (unit == "t") "Change in net credit from default (t CO2e/ha/yr)" else
    "Change in net credit (% of default)"
  default_format <- if (unit == "t") "Default net credit: %.2f t CO2e/ha/yr" else
    "Default net credit: %.2f t CO2e/ha/yr (= 0%%)"
  file_suffix <- if (unit == "t") "" else "_pct"

  draw_tornado(
    ranges = oat_ranges(oat_metric),
    ticks = sweeps[, .(conservation_practice, variable, value = get(oat_metric))],
    fdcic_metric = oat_metric, x_label = x_label, default_format = default_format,
    title = "One-at-a-time sensitivity of annualized net credit to each variable and accounting decision",
    footnote = paste(default_text, "White ticks mark individual levels."),
    plot_path = file.path(output_dir, paste0("tornado_net_credit", file_suffix, ".png"))
  )

  ensemble <- unique(full[, .(conservation_practice, v = get(paste0("ensemble_mean_", full_suffix)))])
  draw_tornado(
    ranges = full_ranges(full_suffix),
    ticks = NULL,
    fdcic_metric = oat_metric, x_label = x_label, default_format = default_format,
    title = "Full sensitivity: level means over every combination of the other variables and decisions",
    footnote = paste0(default_text, "\nBars: range of level means, each averaged over all ",
                     "combinations of the other choices with equal weight. Whiskers: 5th-95th ",
                     "percentile of the effect at the extreme levels across those combinations."),
    plot_path = file.path(output_dir, paste0("tornado_full_sensitivity", file_suffix, ".png")),
    reference_lines = setNames(as.list(ensemble$v), ensemble$conservation_practice),
    reference_label = "Ensemble mean",
    show_fdcic = FALSE,
    x_pad = 0.12  # whisker labels sit near the axis limits without the FD-CIC row
  )

  # Median-centred version
  med_suffix <- if (unit == "t") "vsmed" else "vsmedpct"
  draw_tornado(
    ranges = full_ranges(med_suffix, data = full_median, level_column = "level_value"),
    ticks = NULL,
    fdcic_metric = med_suffix,
    x_label = if (unit == "t") "Deviation of net credit from the ensemble median (t CO2e/ha/yr)" else
      "Deviation of net credit from the ensemble median (% of median)",
    default_format = if (unit == "t") "Ensemble median net credit: %.2f t CO2e/ha/yr" else
      "Ensemble median net credit: %.2f t CO2e/ha/yr (= 0%%)",
    title = "Full sensitivity, centred on the ensemble median of every combination of variables and decisions",
    footnote = paste0("Dotted line: median net credit across all specifications in the sensitivity set (equal weight). ",
                      "Bars: ensemble median plus the median effect of each level, where an effect is the credit\n",
                      "minus the median over that variable's levels for the same combination of the other choices. ",
                      "Whiskers: 5th-95th percentile of the effect at the extreme levels.\n",
                      "Per-bushel credits are shown as credit per bushel x project bushels/ha/yr."),
    plot_path = file.path(output_dir, paste0("tornado_full_sensitivity_median", file_suffix, ".png")),
    header_values = median_values
  )
}

# Publication version of the median-centred tornado ---------------------------
# The x axis shows the net credit itself: each practice's median-centred bars
# and whiskers are shifted back by its ensemble median (dotted line).
# 6.5 in wide (a letter page with 1 in margins), every text element at least
# text_pt at that size, and no title, footnote, or FD-CIC row (the caption
# carries those). Level labels are shortened; the caption should define them.

library(ggplot2)

pub_short_labels <- c("Conv. = RT" = "RT", "Conv.: plow" = "plow", "Conv.: fall cultivator/disk" = "Default",
                      "SOC only" = "None", "Direct N2O, GWP 265" = "Direct N2O",
                      "DEC4 0.0022" = "0.0022", "DEC4 0.0048" = "0.0048", "Per bushel (CI)" = "Per bushel")
pub_ranges <- full_ranges("vsmed", data = full_median, level_column = "level_value")
pub_ranges[, `:=`(low_level = fifelse(low_level %in% names(pub_short_labels), pub_short_labels[low_level], low_level),
                  high_level = fifelse(high_level %in% names(pub_short_labels), pub_short_labels[high_level], high_level))]
pub_ranges[median_values, on = "conservation_practice", ensemble_median := i.default]
pub_ranges[, c("low", "high", "whisker_low", "whisker_high") := lapply(.SD, `+`, ensemble_median),
           .SDcols = c("low", "high", "whisker_low", "whisker_high")]
pub_medians <- data.table(practice = factor(practices[median_values$conservation_practice], levels = practices),
                          x = median_values$default)
pub_rows <- pub_ranges[, .(mean_span = mean(high - low)), by = variable][order(mean_span), variable]
pub_ranges[, `:=`(y = match(variable, pub_rows),
                  left = pmin(low, whisker_low), right = pmax(high, whisker_high),
                  practice = factor(practices[conservation_practice], levels = practices))]
pub_strips <- setNames(sprintf("%s (median %.2f t CO2e/ha/yr)", practices[median_values$conservation_practice],
                               median_values$default), practices[median_values$conservation_practice])

draw_tornado_pub <- function(path, text_pt = 11, ncol = 1, width_in = 6.5, height_in = 8.2, strips = pub_strips,
                             end_labels = TRUE, title_pt = text_pt + 1, family = "sans", median_labels = NULL,
                             median_pt = text_pt - 1, top_break_only = NULL, ranges = pub_ranges,
                             rows = pub_rows, centers = pub_medians, center_label = "Ensemble median",
                             whisker_label = "5th-95th percentile of effect",
                             x_title = expression(Net~credit~(t~CO[2]*e~ha^-1~yr^-1)), whiskers = TRUE,
                             ticks = NULL, legend_box = "vertical") {
  # x limits wide enough for the labels at the whisker ends: approximate text
  # width (0.62 em per character, slightly generous) converted to data units, iterated because the
  # conversion depends on the limits. Panels share one x scale.
  char_in <- 0.62 * text_pt / 72
  gap_in <- 0.06
  row_label_in <- char_in * max(nchar(variable_labels[rows]))
  panel_in <- (width_in - 0.2 - row_label_in - (ncol - 1) * 0.15) / ncol
  lims <- range(c(0, ranges$left, ranges$right))
  if (!end_labels) lims <- lims + c(-1, 1) * 0.04 * diff(lims)
  for (i in seq_len(if (end_labels) 30 else 0)) {
    units_per_in <- diff(lims) / panel_in
    lims <- c(min(ranges$left - (nchar(ranges$low_level) * char_in + gap_in) * units_per_in),
              max(ranges$right + (nchar(ranges$high_level) * char_in + gap_in) * units_per_in))
  }
  gap_units <- gap_in * diff(lims) / panel_in
  data_share <- diff(range(c(ranges$left, ranges$right))) / diff(lims)

  # Optionally label the top x break in one panel only (the others keep the same
  # limits, so the unlabelled space stays as a buffer between panels). Panels
  # get free x scales whose limits differ only by 1e-9, which the break function
  # uses to tell them apart.
  if (is.null(top_break_only)) {
    x_scale <- scale_x_continuous(limits = lims, breaks = seq(ceiling(lims[1]), floor(lims[2]), 1),
                                  expand = expansion(0))
    x_extent <- NULL
    facet_scales <- "fixed"
  } else {
    x_scale <- scale_x_continuous(expand = expansion(0), breaks = function(l) {
      b <- seq(ceiling(l[1] - 1e-6), floor(l[2] + 1e-6), 1)
      if (l[2] > lims[2] + 5e-10) b else head(b, -1)
    })
    x_extent <- data.table(practice = factor(rep(practices, each = 2), levels = practices),
                           x = c(rbind(lims[1], lims[2] + ifelse(practices %in% top_break_only, 1e-9, 0))))
    facet_scales <- "free_x"
  }
  top_pad <- if (is.null(median_labels)) 0.6 else 1.05

  p <- ggplot(ranges) +
    (if (!is.null(x_extent)) geom_blank(data = x_extent, aes(x = x, y = 1))) +
    geom_vline(xintercept = 0, color = "#b5b4ae", linewidth = 0.4) +
    geom_vline(data = centers, aes(xintercept = x, linetype = center_label), linewidth = 0.5) +
    (if (whiskers) geom_errorbar(aes(y = y, xmin = whisker_low, xmax = whisker_high, linetype = whisker_label),
                                 orientation = "y", width = 0.3, linewidth = 0.4, color = axis_ink)) +
    geom_rect(aes(xmin = low, xmax = high, ymin = y - 0.32, ymax = y + 0.32, fill = group)) +
    # white tick at each level's value inside the bar
    (if (!is.null(ticks)) geom_segment(data = ticks, aes(x = x, xend = x, y = y - 0.32, yend = y + 0.32),
                                       color = "white", linewidth = 0.5)) +
    (if (end_labels) list(
      # white label background so the zero line and grid lines do not cross the text
      geom_label(aes(x = left - gap_units, y = y, label = low_level), hjust = 1, size = text_pt / .pt, color = axis_ink,
                 family = family, fill = "white", linewidth = 0, label.padding = unit(1, "pt")),
      geom_label(aes(x = right + gap_units, y = y, label = high_level), hjust = 0, size = text_pt / .pt, color = axis_ink,
                 family = family, fill = "white", linewidth = 0, label.padding = unit(1, "pt")))) +
    (if (!is.null(median_labels))
      geom_label(data = data.table(practice = factor(names(median_labels), levels = practices), label = median_labels),
                 aes(x = lims[1], y = length(rows) + 0.8, label = label), hjust = 0, size = median_pt / .pt,
                 family = family, color = "#0b0b0b", fill = "white", linewidth = 0, label.padding = unit(1, "pt"))) +
    facet_wrap(~practice, ncol = ncol, labeller = labeller(practice = strips), scales = facet_scales) +
    scale_y_continuous(breaks = seq_along(rows), labels = variable_labels[rows],
                       expand = expansion(add = c(0.6, top_pad))) +
    x_scale +
    scale_fill_manual(values = group_colors, labels = c(biophysical = "Biophysical variable",
                                                        accounting = "Accounting decision"), name = NULL) +
    scale_linetype_manual(values = if (whiskers) setNames(c("solid", "dotted"), c(whisker_label, center_label)) else
                            setNames("dotted", center_label), name = NULL) +
    guides(fill = guide_legend(order = 1), linetype = guide_legend(order = 2)) +
    labs(x = x_title, y = NULL) +
    theme_minimal(base_size = text_pt, base_family = family) +
    theme(text = element_text(size = text_pt, color = "#0b0b0b", family = family),
          axis.text = element_text(size = text_pt, color = "#0b0b0b"),
          axis.title.x = element_text(size = title_pt, margin = margin(t = 6)),
          strip.text = element_text(size = title_pt, face = "bold", hjust = 0),
          legend.text = element_text(size = text_pt),
          legend.position = "bottom", legend.box = legend_box, legend.spacing.y = unit(0, "pt"),
          legend.margin = margin(0, 0, 0, 0), legend.key.width = unit(22, "pt"),
          panel.grid.major.y = element_blank(), panel.grid.minor = element_blank(),
          panel.spacing = unit(10, "pt"), plot.margin = margin(4, 6, 4, 4))
  ggsave(paste0(path, ".png"), p, width = width_in, height = height_in, dpi = 600, bg = "white")
  ggsave(paste0(path, ".pdf"), p, width = width_in, height = height_in, bg = "white")
  message(sprintf("Wrote %s.png/.pdf (%d column(s), %g pt %s; bars and whiskers use %.0f%% of each panel width)",
                  path, ncol, text_pt, family, 100 * data_share))
  invisible(data_share)
}

draw_tornado_pub(file.path(output_dir, "tornado_full_sensitivity_median_pub"))
# Side by side, without the level labels at the whisker ends (they do not fit in
# three columns; the caption must give the extreme levels). Same font as the
# other publication figures, at 8 pt text and 9 pt titles at 6.5 in; the
# practice median is a plain line under each panel title, and only the cover
# crop panel labels the top x break.
draw_tornado_pub(file.path(output_dir, "tornado_full_sensitivity_median_pub_horizontal"), ncol = 3, height_in = 4.3,
                 end_labels = FALSE, text_pt = 8, title_pt = 9, median_pt = 8,
                 strips = setNames(practices, practices),
                 median_labels = setNames(sprintf("Median %.2f", median_values$default),
                                          practices[median_values$conservation_practice]),
                 top_break_only = "Cover crop")

# Default-centred publication tornado ------------------------------------------
# The same full-factorial construction, but an effect is the credit at a level
# minus the credit at that variable's default level for the same combination of
# the other choices, so every variable's default level sits on the default
# line. Bars span the default credit plus each level's median effect; whiskers
# the 5th-95th percentile of the effects at the extreme levels.
full_default <- rbindlist(lapply(names(practices), function(practice) {
  practice_rows <- results[conservation_practice == practice]
  default_value <- default_values[conservation_practice == practice, default]
  rbindlist(lapply(variables, function(v) {
    others <- setdiff(variables, v)
    effects <- practice_rows[, {
      lv <- as.character(get(v))
      .(level = lv, effect = net_credit_mg_co2e_ha_yr - net_credit_mg_co2e_ha_yr[lv == as.character(defaults[[v]])])
    }, by = others]
    effects[, .(level_value_abs = default_value + median(effect),
                effect_q05_abs = default_value + quantile(effect, 0.05, names = FALSE),
                effect_q95_abs = default_value + quantile(effect, 0.95, names = FALSE),
                specifications = .N), by = level][
      , `:=`(conservation_practice = practice, variable = v, default_net_credit_mg_co2e_ha_yr = default_value)]
  }))
}))
full_default[, `:=`(level_label = level_labels[level], variable_label = variable_labels[variable],
                    group = variable_groups[variable])]
full_default_path <- file.path(output_dir, "tornado_full_sensitivity_default.csv")
fwrite(full_default, full_default_path)

def_ranges <- full_ranges("abs", data = full_default, level_column = "level_value")
def_ranges[, `:=`(low_level = fifelse(low_level %in% names(pub_short_labels), pub_short_labels[low_level], low_level),
                  high_level = fifelse(high_level %in% names(pub_short_labels), pub_short_labels[high_level], high_level))]
def_rows <- def_ranges[, .(mean_span = mean(high - low)), by = variable][order(mean_span), variable]
def_ranges[, `:=`(y = match(variable, def_rows),
                  left = pmin(low, whisker_low), right = pmax(high, whisker_high),
                  practice = factor(practices[conservation_practice], levels = practices))]
def_centers <- data.table(practice = factor(practices[default_values$conservation_practice], levels = practices),
                          x = default_values$default)
draw_tornado_pub(file.path(output_dir, "tornado_full_sensitivity_default_pub_horizontal"), ncol = 3, height_in = 4.3,
                 end_labels = FALSE, text_pt = 8, title_pt = 9, median_pt = 8,
                 strips = setNames(practices, practices),
                 median_labels = setNames(sprintf("Default %.2f", default_values$default),
                                          practices[default_values$conservation_practice]),
                 top_break_only = "Cover crop", ranges = def_ranges, rows = def_rows, centers = def_centers,
                 center_label = "Default specification", whisker_label = "5th-95th percentile of change from default",
                 x_title = expression(Annualized~net~benefit~(t~CO[2]*e~ha^-1~yr^-1)))

# Option 1: classic tornado without whiskers; white ticks mark each level's
# median change, so the bar reads as the range across discrete levels.
def_ranges_bars <- copy(def_ranges)[, `:=`(left = low, right = high)]
def_ticks <- full_default[, .(practice = factor(practices[conservation_practice], levels = practices),
                              y = match(variable, def_rows), x = level_value_abs)]
draw_tornado_pub(file.path(output_dir, "tornado_full_sensitivity_default_pub_horizontal_ticks"), ncol = 3,
                 height_in = 4.3, end_labels = FALSE, text_pt = 8, title_pt = 9, median_pt = 8,
                 strips = setNames(practices, practices),
                 median_labels = setNames(sprintf("Default %.2f", default_values$default),
                                          practices[default_values$conservation_practice]),
                 top_break_only = "Cover crop", ranges = def_ranges_bars, rows = def_rows, centers = def_centers,
                 center_label = "Default specification", whiskers = FALSE, ticks = def_ticks, legend_box = "horizontal",
                 x_title = expression(Annualized~net~benefit~(t~CO[2]*e~ha^-1~yr^-1)))

# Option 2: dot-and-interval plot. One point per level at the default plus the
# level's median change from the default level; the line spans the 5th-95th
# percentile of that change across all combinations of the other choices.
# Factors are ordered as in the tornado (widest bar at the top).
dot_short_labels <- c("DEC4 default (0.0025)" = "0.0025", "DEC4 0.0022" = "0.0022", "DEC4 0.0048" = "0.0048",
                      "Conv.: fall cultivator/disk" = "Fall cultivator/disk", "Conv.: plow" = "Plow",
                      "Conv. = RT" = "Reduced till", "Direct N2O, GWP 265" = "Direct N2O",
                      "Per bushel (CI)" = "Per bushel")
dot_label <- function(x) fifelse(x %in% names(dot_short_labels), dot_short_labels[x], x)
dot <- copy(full_default)
dot[, `:=`(practice = factor(practices[conservation_practice], levels = practices),
           factor_label = factor(variable_labels[variable], levels = variable_labels[rev(def_rows)]),
           level_short = factor(dot_label(level_label), levels = rev(unique(dot_label(level_labels)))),
           is_default = level == vapply(variable, function(v) as.character(defaults[[v]]), ""))]
dot_text_pt <- 8
dot_plot <- ggplot(dot, aes(y = level_short)) +
  geom_vline(xintercept = 0, color = "#b5b4ae", linewidth = 0.4) +
  geom_vline(data = def_centers, aes(xintercept = x, linetype = "Default specification"), linewidth = 0.5) +
  geom_linerange(aes(xmin = effect_q05_abs, xmax = effect_q95_abs, color = group), linewidth = 0.6) +
  geom_point(aes(x = level_value_abs, color = group, shape = is_default), size = 1.8, fill = "white", stroke = 0.7) +
  facet_grid(factor_label ~ practice, scales = "free_y", space = "free_y", switch = "y") +
  scale_color_manual(values = group_colors, labels = c(biophysical = "Biophysical variable",
                                                       accounting = "Accounting decision"), name = NULL) +
  scale_shape_manual(values = c("TRUE" = 21, "FALSE" = 16),
                     labels = c("TRUE" = "Default level", "FALSE" = "Median change from default level"),
                     breaks = c("FALSE", "TRUE"), name = NULL) +
  scale_linetype_manual(values = c("Default specification" = "dotted"), name = NULL) +
  scale_x_continuous(breaks = seq(-2, 5, 1)) +
  guides(color = guide_legend(order = 1), shape = guide_legend(order = 2), linetype = guide_legend(order = 3)) +
  labs(x = expression(Annualized~net~benefit~(t~CO[2]*e~ha^-1~yr^-1)), y = NULL) +
  theme_minimal(base_size = dot_text_pt) +
  theme(text = element_text(size = dot_text_pt, color = "#0b0b0b"),
        axis.text = element_text(size = dot_text_pt, color = "#0b0b0b"),
        axis.title.x = element_text(size = dot_text_pt + 1, margin = margin(t = 6)),
        strip.text.x = element_text(size = dot_text_pt + 1, face = "bold", hjust = 0),
        strip.text.y.left = element_text(size = dot_text_pt, face = "bold", angle = 0, hjust = 1),
        strip.placement = "outside",
        legend.position = "bottom", legend.box = "vertical", legend.spacing.y = unit(0, "pt"),
        legend.margin = margin(0, 0, 0, 0), legend.key.width = unit(22, "pt"),
        panel.grid.major.y = element_line(color = "#f3f3f1", linewidth = 0.3),
        panel.grid.minor = element_blank(), panel.border = element_rect(color = "#d8d7d2", fill = NA, linewidth = 0.3),
        panel.spacing.x = unit(10, "pt"), panel.spacing.y = unit(3, "pt"), plot.margin = margin(4, 6, 4, 4))
dot_path <- file.path(output_dir, "dot_interval_full_sensitivity_default_pub")
ggsave(paste0(dot_path, ".png"), dot_plot, width = 6.5, height = 7.5, dpi = 600, bg = "white")
ggsave(paste0(dot_path, ".pdf"), dot_plot, width = 6.5, height = 7.5, bg = "white")
message("Wrote ", dot_path, ".png/.pdf")

message("Wrote sweep values to ", sweep_path)
message("Wrote full-sensitivity values to ", full_path)
message("Wrote default-centred full-sensitivity values to ", full_default_path)
