# Alternative conventional (counterfactual) schedules for 2020-2050, derived
# from the v2 continuous schedules so they share headers, weather, crop, N, and
# harvest events:
#   exp_corn_CONVPLOW_cont.sch  spring field cultivator (D491) + fall moldboard
#                               plow (K491) on day 297, as in v1
#                               cnt2_corn_sDfK; from exp_corn_CONV_cont.sch with
#                               the fall field cultivator and tandem disk (F491)
#                               replaced by K491
#   exp_corn_CONVRT_cont.sch    spring row cultivator (B491) + fall sweeps and
#                               tandem disks (E491) on day 297, as in v1
#                               cnt2_corn_sBfE; same management as
#                               exp_corn_RT_cont.sch
# Run build_fertilizer_schedules.R afterwards for the UAN10/UAN30 variants.
# Existing files are verified, not overwritten.
#
# Usage: Rscript analysis/build_conventional_alternatives.R

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

repo_root <- normalizePath(file.path(get_script_dir(), ".."), mustWork = TRUE)
schedule_dir <- file.path(repo_root, "sites", "enfarm", "v2schedules")

replace_once <- function(lines, pattern, replacement, path) {
  hit <- grep(pattern, lines)
  if (length(hit) != 1L) stop("Expected one line matching '", pattern, "' in ", path, call. = FALSE)
  lines[hit] <- replacement
  lines
}

write_or_verify <- function(lines, path) {
  if (file.exists(path)) {
    if (!identical(readLines(path, warn = FALSE), lines)) {
      stop("Existing schedule differs from generated content: ", path, call. = FALSE)
    }
    message("Verified ", basename(path))
    return(invisible(FALSE))
  }
  writeLines(lines, path, useBytes = TRUE)
  message("Wrote ", basename(path))
  invisible(TRUE)
}

conv_path <- file.path(schedule_dir, "exp_corn_CONV_cont.sch")
conv <- readLines(conv_path, warn = FALSE)
plow <- replace_once(conv, "^[[:space:]]*1[[:space:]]+297[[:space:]]+CULT[[:space:]]+F491",
                     "   1   297 CULT K491	#Moldboard Plow",
                     conv_path)
plow <- replace_once(plow, "Block #", "1            Block # continuous conventional: field cultivator + fall moldboard plow",
                     conv_path)
write_or_verify(plow, file.path(schedule_dir, "exp_corn_CONVPLOW_cont.sch"))

rt_path <- file.path(schedule_dir, "exp_corn_RT_cont.sch")
rt <- readLines(rt_path, warn = FALSE)
if (!any(grepl("CULT[[:space:]]+B491", rt)) || !any(grepl("CULT[[:space:]]+E491", rt))) {
  stop("Expected B491 and E491 tillage in ", rt_path, call. = FALSE)
}
convrt <- replace_once(rt, "Block #", "1            Block # continuous conventional: row cultivator + fall sweeps/tandem disks (= reduced till)",
                       rt_path)
write_or_verify(convrt, file.path(schedule_dir, "exp_corn_CONVRT_cont.sch"))
