# DayCent parameter files (not included)

DayCent parameter libraries (`crop.100`, `cult.100`, `fert.100`, `fix.100`, `harv.100`, `omad.100`, and the others) are not included in this repository. The DayCent model and its v491 parameterization files are © Colorado State University and are available through LandEngine (https://landengine.org/). DayCent-CABBI and the Energy Farm parameterization are described in Hartman et al. (2022), *Ecosphere* 13: e4292, https://doi.org/10.1002/ecs2.4292.

`analysis/run_daycent_plan.R` expects the libraries in this folder. The site files (`enfarm_eq.100`, `enfarm_base.100`, `enfarm_cnt.100`, the site copies of the libraries, `sitepar.in`, and `soils.in`) belong in `../sites/enfarm/` and are also not included.

The cover crop uses `CCRYE` in `crop.100`: the DayCent v491 "Cereal Rye for cover crop" values, with the 40 DayCent-CABBI parameters that v491 lacks filled from `BAR` (see `analysis/README.md`). The cover-crop termination uses `HC` and the reduced-tillage and conventional schedules use the v491 cultivation events `B491`, `D491`, `E491`, `F491`, and `K491` in `cult.100`.
