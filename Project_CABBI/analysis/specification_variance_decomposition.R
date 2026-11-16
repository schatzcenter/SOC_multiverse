# ANOVA-style variance decomposition of a deterministic specification ensemble.
#
# Each conservation practice is decomposed separately. A practice's ensemble
# is its enumerated sensitivity-set specifications in accounting_results.csv: each
# combination of biophysical and model inputs (N rate, historic land use,
# cycling, DEC4) and accounting choices (carbon pool, horizon, counterfactual,
# N2O treatment, functional unit) gives one deterministic DayCent-based
# credit. Practice is not a factor: the difference between practices is not
# uncertainty in a practice's credit.
# This is not an inferential ANOVA of independent observations: there is no
# sampling error, so F statistics and p-values are not reported.
#
# Estimand: the variance of annualized net credit when every enumerated
# specification is weighted equally, i.e. under a discrete uniform
# distribution over the specification grid, and the share of that variance
# attributable to each factor and interaction. Shares therefore depend on
# which levels are enumerated and on treating each as equally plausible.
#
# The grid is a balanced full factorial with one value per cell, so each
# term's sum of squares is computed exactly from marginal means. Terms run
# through three-way interactions; four-way and higher interactions form the
# remainder. Counterfactuals are the three conventional definitions. The functional
# unit enters through its per-area value: the area credit, or for per-bushel
# (carbon intensity) crediting, credit per bushel x project bushels/ha/yr.

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

response <- "net_credit_mg_co2e_ha_yr"
factor_groups <- c(
  n_rate = "biophysical",
  historic_land_use = "biophysical",
  cycling_frequency = "biophysical",
  dec4 = "biophysical",
  carbon_pool = "accounting",
  horizon_years = "accounting",
  counterfactual = "accounting",
  n2o_option = "accounting",
  functional_unit = "accounting"
)
factor_labels <- c(
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
factors <- names(factor_groups)
weighting <- "discrete uniform over enumerated specifications"

results <- fread(results_path, select = c("conservation_practice", factors, response))

max_order <- 3L  # main effects through three-way interactions; higher is remainder
term_types <- c("main", "two-way", "three-way")
remainder_label <- paste0("Remainder (", max_order + 1L, "-way+)")

# Exact sums of squares for a balanced complete factorial with one value per
# cell. A term's effect in each cell is the inclusion-exclusion sum of the
# marginal means of every subset of its factors:
# sum over T in S of (-1)^(|S|-|T|) mean_T. Dividing a sum of squares by the
# number of specifications gives that term's contribution to the variance
# under the uniform weighting.
decompose <- function(dt, factors = names(factor_groups)) {
  levels_per_factor <- vapply(factors, function(f) uniqueN(dt[[f]]), integer(1))
  if (nrow(unique(dt[, ..factors])) != nrow(dt) || prod(levels_per_factor) != nrow(dt)) {
    stop("Specifications are not a balanced full factorial with one value per cell.",
         call. = FALSE)
  }
  y <- dt[[response]]
  grand_mean <- mean(y)
  total_ss <- sum((y - grand_mean)^2)

  mean_cache <- new.env()
  marginal_means <- function(cols) {
    key <- paste(cols, collapse = ":")
    if (is.null(mean_cache[[key]])) {
      mean_cache[[key]] <- dt[, .(m = mean(get(response)), n = .N), by = cols]
    }
    mean_cache[[key]]
  }

  term_sets <- unlist(lapply(seq_len(max_order), function(k) {
    combn(factors, k, simplify = FALSE)
  }), recursive = FALSE)
  terms <- rbindlist(lapply(term_sets, function(term_factors) {
    cell <- copy(marginal_means(term_factors))
    effect <- cell$m
    for (k in seq_len(length(term_factors) - 1L)) {
      for (subset in combn(term_factors, k, simplify = FALSE)) {
        sub_values <- marginal_means(subset)[cell, on = subset, x.m]
        effect <- effect + (-1)^(length(term_factors) - k) * sub_values
      }
    }
    effect <- effect + (-1)^length(term_factors) * grand_mean
    groups <- unique(factor_groups[term_factors])
    data.table(
      term = paste(term_factors, collapse = ":"),
      label = paste(factor_labels[term_factors], collapse = " x "),
      term_type = term_types[length(term_factors)],
      group = if (length(groups) == 1L) groups else "biophysical x accounting",
      df = prod(levels_per_factor[term_factors] - 1L),
      ss = sum(cell$n * effect^2)
    )
  }))

  terms <- rbind(
    terms,
    data.table(term = "remainder", label = remainder_label, term_type = "remainder",
               group = "remainder", df = nrow(dt) - 1L - sum(terms$df),
               ss = total_ss - sum(terms$ss))
  )
  terms[, `:=`(
    variance_contribution = ss / nrow(dt),
    share_of_variance_pct = 100 * ss / total_ss,
    n_specifications = nrow(dt),
    weighting = weighting,
    ensemble_mean = grand_mean,
    ensemble_variance = total_ss / nrow(dt)
  )]
  terms[]
}

# One ensemble per practice: the variance among that practice's specifications.
practice_names <- c(nt = "No-till", rt = "Reduced till", cc = "Cover crop")
decomposition <- rbindlist(lapply(names(practice_names), function(p) {
  out <- decompose(results[conservation_practice == p][, conservation_practice := NULL])
  out[, ensemble := paste0("practice_", p)]
  out
}))
setorder(decomposition, ensemble, -share_of_variance_pct)
setcolorder(decomposition, c("ensemble", "term", "label", "term_type", "group", "df", "ss",
                             "variance_contribution", "share_of_variance_pct"))
decomposition_path <- file.path(output_dir, "specification_variance_decomposition.csv")
fwrite(decomposition, decomposition_path)

group_table <- decomposition[, .(share_of_variance_pct = sum(share_of_variance_pct)),
                             by = .(ensemble, group)]
setorder(group_table, ensemble, -share_of_variance_pct)
group_path <- file.path(output_dir, "specification_variance_by_group.csv")
fwrite(group_table, group_path)

# Figure: top terms by share of ensemble variance, colored by factor group ----

group_colors <- c(biophysical = "#2a78d6", accounting = "#eb6834",
                  "biophysical x accounting" = "#1baf7a", remainder = "#8a8984")
group_labels <- c(biophysical = "Biophysical", accounting = "Accounting",
                  "biophysical x accounting" = "Biophysical x accounting",
                  remainder = remainder_label)
ensemble_titles <- setNames(practice_names, paste0("practice_", names(practice_names)))
axis_ink <- "#52514e"
top_n <- 15L

draw_figure <- function(names_to_plot, plot_path, main_title) {
  # Panels stacked vertically (one row per ensemble).
  k <- length(names_to_plot)
  png(plot_path, width = 2200, height = 400 + 1500 * k, res = 200)
  par(mfrow = c(k, 1), mar = c(4.2, 21, 4.2, 3.2), oma = c(5.4, 0, 2.6, 0),
      mgp = c(2.4, 0.6, 0))
  for (name in names_to_plot) {
    terms <- decomposition[ensemble == name & term_type != "remainder"][
      order(-share_of_variance_pct)][seq_len(top_n)]
    terms <- rbind(terms, decomposition[ensemble == name & term_type == "remainder"])
    terms <- terms[rev(seq_len(nrow(terms)))]
    group_share <- group_table[ensemble == name]
    n_specs <- terms$n_specifications[1]
    bar_centers <- barplot(terms$share_of_variance_pct, horiz = TRUE, names.arg = terms$label,
                           las = 1, col = unname(group_colors[terms$group]), border = "white",
                           xlim = c(0, max(terms$share_of_variance_pct) * 1.18),
                           cex.names = 0.78, xlab = "Share of ensemble variance (%)",
                           col.axis = axis_ink, col.lab = axis_ink, axes = FALSE)
    axis(1, col.axis = axis_ink, cex.axis = 0.85)
    text(terms$share_of_variance_pct, bar_centers, sprintf("%.1f", terms$share_of_variance_pct),
         pos = 4, cex = 0.72, col = "#0b0b0b", xpd = NA)
    subtitle <- paste(sprintf("%s %.0f%%", group_labels[group_share$group],
                              group_share$share_of_variance_pct), collapse = " | ")
    title(main = sprintf("%s; %s specifications", ensemble_titles[[name]],
                         format(n_specs, big.mark = ",")),
          font.main = 1, cex.main = 0.95, line = 2.2)
    mtext(subtitle, side = 3, line = 0.8, cex = 0.62, col = axis_ink)
  }
  par(fig = c(0, 1, 0, 1), oma = c(0, 0, 0, 0), mar = c(0, 0, 0, 0), new = TRUE)
  plot.new()
  legend("bottom", legend = unname(group_labels), fill = unname(group_colors),
         border = NA, horiz = TRUE, bty = "n", cex = 0.85, inset = c(0, 0.055 * 1900 / (400 + 1500 * k)))
  mtext(paste("ANOVA-style decomposition of a deterministic specification ensemble, not an",
              "inferential ANOVA. Shares are of the variance of net credit with every enumerated",
              "specification weighted equally\n(discrete uniform), so they depend on which levels",
              "are enumerated and assume each is equally plausible."),
        side = 1, line = -1.6, cex = 0.62, col = axis_ink)
  mtext(main_title, side = 3, line = -1.6, cex = 1.05, font = 2)
  dev.off()
  message("Wrote figure to ", plot_path)
}

draw_figure(paste0("practice_", names(practice_names)),
            file.path(output_dir, "specification_variance_by_practice.png"),
            paste("Variance in annualized net credit (Mg CO2e/ha/yr) within each practice's specifications:",
                  "top 15 terms"))

message("Wrote decomposition table to ", decomposition_path)
message("Wrote group summary to ", group_path)
print(group_table)
