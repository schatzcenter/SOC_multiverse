# Share of the variance in the annualized net benefit explained by accounting
# decisions, farm and model inputs, their interactions, and the higher-order
# remainder, one stacked bar per conservation practice (paper Figure 3).
#
# Reads outputs/summary/specification_variance_by_group.csv (written by
# specification_variance_decomposition.R).
# Writes outputs/summary/variance_by_group_pub.png/.pdf.
#
# Usage: Rscript analysis/plot_variance_groups.R

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

groups <- read.csv(file.path(output_dir, "specification_variance_by_group.csv"))
practices <- c(nt = "No-till", rt = "Reduced till", cc = "Cover crop")
group_labels <- c(accounting = "Accounting decisions",
                  biophysical = "Farm and model inputs",
                  "biophysical x accounting" = "Input × accounting interactions",
                  remainder = "Higher-order remainder (4-way+)")
grp <- function(p, g) groups$share_of_variance_pct[groups$ensemble == paste0("practice_", p) & groups$group == g]

m <- sapply(names(practices), function(p) sapply(names(group_labels), function(g) grp(p, g)))
colnames(m) <- practices
m <- m[, rev(colnames(m))]
cols <- c("#E8693A", "#2A78D6", "#1AAE87", "grey70")

draw <- function() {
  op <- par(mar = c(7.5, 7, 0.5, 1), xpd = TRUE)
  bp <- barplot(m, horiz = TRUE, las = 1, col = cols, border = NA, xlim = c(0, 100))
  mtext("Share of variance (%)", side = 1, line = 2.5)
  mids <- apply(m, 2, function(v) cumsum(v) - v / 2)
  for (j in seq_len(ncol(m))) {
    show <- m[, j] >= 5
    text(mids[show, j], bp[j], paste0(round(m[show, j]), "%"), col = "white", cex = 0.85)
  }
  legend("bottom", inset = c(0, -0.95), legend = group_labels, fill = cols,
         border = NA, ncol = 2, bty = "n", cex = 0.85)
  par(op)
}

out_path <- file.path(output_dir, "variance_by_group_pub")
png(paste0(out_path, ".png"), width = 7, height = 3, units = "in", res = 600)
draw()
invisible(dev.off())
pdf(paste0(out_path, ".pdf"), width = 7, height = 3)
draw()
invisible(dev.off())
message("Wrote ", out_path, ".png/.pdf")
