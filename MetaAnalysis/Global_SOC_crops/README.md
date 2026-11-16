# Empirical data (not included)

The *Global Soil Carbon Fractions: Regenerative + Conventional Croplands* dataset is not redistributed in this repository. It is available through LandEngine (https://landengine.org/).

> A. M. Prairie, A. E. King, and M. F. Cotrufo, "Restoring particulate and mineral-associated organic carbon through regenerative agriculture," *Proc. Natl. Acad. Sci.*, vol. 120, no. 21, p. e2217481120, May 2023, doi: [10.1073/pnas.2217481120](https://doi.org/10.1073/pnas.2217481120).

`../SOCMetaAnalysis.Rmd` expects the following files in this folder, so it will not run without the dataset:

- `globalsocfractions_crops.csv`
- `globalsocfractions_crops_filtered_top20_referenced.csv` (the dataset filtered to corn studies measured to at least 20 cm, with each treatment assigned a conventional reference; the reference assignments are not shared)

The derived files that `SOCMetaAnalysis.Rmd` writes (`empirical_soc_pairs.csv`, `empirical_soc_study_means.csv`, `meta_analysis_results.csv`, and the covariate tables) are also not included, so `../plot_duration_model_bands.R` (Figure 4) needs them to be regenerated first.
