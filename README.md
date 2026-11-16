# SOC_multiverse

Code and derived data for *Conservation agriculture and soil carbon accumulation: modeled sensitivity, accounting choices, and empirical heterogeneity* (Burton-Tauzer, Vergara, and Fingerman).

DayCent-CABBI simulates 30 years (2020–2050) of continuous corn at the University of Illinois Energy Farm under conventional management, no-till (NT), reduced tillage (RT), and a cereal rye cover crop (CC). A full-factorial specification grid crosses 108 farm and model input scenarios (N rate × land-use history × practice continuity × DEC4) with 180 accounting protocols (counterfactual × carbon pool × horizon × N₂O treatment × functional unit), giving 19,440 specifications per practice. The modeled spread is then compared with field measurements of SOC change under the same practices in corn.

## Repository layout

```
Project_CABBI/                 DayCent-CABBI scenario modeling and sensitivity analysis
  100libraryfiles/             placeholder: DayCent parameter files are not included
  sites/enfarm/                weather, output-definition, and management schedule files
    v1schedules/, v2schedules/ schedule templates and generated variants
  analysis/                    R pipeline (see analysis/README.md for each step)
  outputs/summary/             compiled model output, accounting results, paper figures
MetaAnalysis/                  empirical synthesis code and the model-versus-field figure
  Global_SOC_crops/            placeholder: the empirical dataset is not included
```

## Paper figures and tables

| Item | Script | Output |
|---|---|---|
| Figure 1 | `Project_CABBI/analysis/plot_default_soc_net.R` | `outputs/summary/default_soc_and_net_soc_pub.png` |
| Figure 2 | `Project_CABBI/analysis/plot_tornado.R` | `outputs/summary/tornado_full_sensitivity_default_pub_horizontal_ticks.png` |
| Figure 3 | `Project_CABBI/analysis/plot_variance_groups.R` | `outputs/summary/variance_by_group_pub.png` |
| Figure 4 | `MetaAnalysis/plot_duration_model_bands.R --soc-only` | `MetaAnalysis/duration_vs_net_soc_band_split_soc_only_pub.png` |
| Table 1 (grid) | `Project_CABBI/analysis/scenario_levels.csv`, `accounting_options.csv` | |
| Table 3 (empirical) | `MetaAnalysis/SOCMetaAnalysis.Rmd` | `empirical_soc_study_means.csv` (not included; needs the dataset) |
| Variance shares (Results, SI) | `Project_CABBI/analysis/specification_variance_decomposition.R` | `specification_variance_decomposition.csv`, `specification_variance_by_group.csv`, `specification_variance_by_practice.png` |
| Ensemble medians and central 95% | `Project_CABBI/analysis/plot_ensemble_distribution.R` | `ensemble_distribution_summary.csv` |
| Default results | `Project_CABBI/analysis/summarize_default_results.R` | `default_results_summary.csv` |
| Heterogeneity (M2, reviewer response) | `MetaAnalysis/SOCMetaAnalysis.Rmd` | `meta_analysis_results.csv` (not included; needs the dataset) |

## Reproducing the results

Requires R (tested with 4.6) and the packages `data.table`, `dplyr`, `tidyr`, `ggplot2`, and, for the meta-analysis, `metafor` and `clubSandwich`.

**From the included outputs (no DayCent needed).** `outputs/summary/daycent_annual_summary.csv` and `accounting_results.csv` are included, so Figures 1–3 and the model summaries can be regenerated directly. Figure 4 also needs the empirical files written by `SOCMetaAnalysis.Rmd` (see below).

```sh
cd Project_CABBI
Rscript analysis/summarize_default_results.R
Rscript analysis/specification_variance_decomposition.R
Rscript analysis/plot_default_soc_net.R
Rscript analysis/plot_tornado.R
Rscript analysis/plot_variance_groups.R
Rscript analysis/plot_ensemble_distribution.R
cd ../MetaAnalysis
Rscript plot_duration_model_bands.R --soc-only   # needs empirical_soc_study_means.csv
```

**From the DayCent runs.** DayCent-CABBI is not included: neither the executables (`DayCent_CABBI_test.exe`, `list100_DayCent_CABBI.exe`, expected in `Project_CABBI/executables/`) nor the parameter files (`.100` libraries, site `.100` files, `sitepar.in`, `soils.in`; see `Project_CABBI/100libraryfiles/README.md`). DayCent is available through LandEngine (https://landengine.org/). With those in place, run from `Project_CABBI/`:

1. `build_scenario_metadata.R` → `scenario_matrix.csv`
2. `build_conventional_alternatives.R`, `build_cycle_schedules.R`, `build_fertilizer_schedules.R` (schedules are already included)
3. `build_daycent_run_plan.R` → `daycent_run_plan.csv`
4. `run_daycent_plan.R` (about 1,700 runs; outputs go to `sites/enfarm/outputs/`)
5. `extract_bin_pools.R`, `compile_outputs.R` → `daycent_annual_summary.csv`
6. `calculate_credit_values.R` → `accounting_results.csv`
7. the figure scripts above

**Empirical synthesis.** The *Global Soil Carbon Fractions: Regenerative + Conventional Croplands* dataset is not included in this repository. It is available through LandEngine (https://landengine.org/):

> A. M. Prairie, A. E. King, and M. F. Cotrufo, "Restoring particulate and mineral-associated organic carbon through regenerative agriculture," *Proc. Natl. Acad. Sci.*, vol. 120, no. 21, p. e2217481120, May 2023, doi: [10.1073/pnas.2217481120](https://doi.org/10.1073/pnas.2217481120).

`SOCMetaAnalysis.Rmd` shows how the dataset was filtered, paired, and summarized, but it will not run without the dataset and the reference assignments (see `MetaAnalysis/Global_SOC_crops/README.md`). The derived empirical files are not included either.

`MetaAnalysis/20206FDCIC_ChIL.csv` holds the 2026 USDA FD-CIC soil carbon values for Champaign County, Illinois (0–30 cm), shown in Figure 4.

## Notes

- `daycent_annual_summary.csv` (~18 MB) and `accounting_results.csv` (~12 MB) are under GitHub's 100 MB file limit.

## Third-party data and software

- DayCent and its parameter files are © Colorado State University and are not redistributed here. DayCent-CABBI and the Energy Farm parameterization are from Hartman et al. (2022), *Ecosphere* 13: e4292.
- The empirical dataset is from Prairie et al. (2023) and is available through LandEngine.
