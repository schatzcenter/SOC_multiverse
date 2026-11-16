# Scenario Metadata

This folder starts the reproducible scenario metadata workflow for the SOC credit uncertainty analysis.

## Files

- `scenario_levels.csv`: editable list of factor levels.
- `set_aside_scenarios.csv`: earlier scenarios kept in the matrix for separate analyses (`analysis_set = "set_aside"`), not used in the sensitivity or range analyses. Replaces `supplemental_scenarios.csv`.
- `build_scenario_metadata.R`: expands active factorial levels (the sensitivity set) into `scenario_matrix.csv` and appends the set-aside scenarios.
- `build_conventional_alternatives.R`: writes the two alternative conventional schedules (`CONVPLOW`, `CONVRT`).
- `scenario_matrix.csv`: generated scenario table used by later DayCent runner and accounting scripts.
- `schedule_registry.csv`: editable schedule provenance and override table.
- `build_daycent_run_plan.R`: turns the scenario matrix into staged DayCent runs.
- `build_cycle_schedules.R`: generates repeated conservation/conventional cycle schedules from the v1 Enfarm templates.
- `build_fertilizer_schedules.R`: generates UAN/no-fertilizer variants for continuous, cycling, and one-time reversion schedules, plus the HLU-expanded supplemental scenario list.
- `daycent_run_plan.csv`: generated run plan for `eq`, `base`, `cnt`, and `exp` stages.
- `run_daycent_plan.R`: cautious runner for selected ready rows in the run plan.
- `extract_bin_pools.R`: runs list100 on each exp-stage `.bin` to extract annual `somtc`, `totc`, `totsysc`, and N volatilization accumulators.
- `compile_outputs.R`: compiles existing DayCent output folders into annual summary tables.
- `accounting_options.csv`: editable accounting options (carbon pools, horizons, counterfactuals, N2O treatments).
- `accounting_rules.csv`: generated cross of the active accounting options, one row per rule.
- `calculate_credit_values.R`: calculates annualized credit values for every project scenario under every accounting rule.
- `specification_variance_decomposition.R`: ANOVA-style variance decomposition of each practice's deterministic specification ensemble (biophysical inputs x accounting choices).
- `credit_horizon_functions.R`: per-horizon credit calculation, used by `../MetaAnalysis/plot_duration_model_bands.R` (Figure 4).
- `summarize_default_results.R`: default-specification summary (Table of default results, Figure 1 values).
- `plot_default_soc_net.R`: Figure 1.
- `plot_tornado.R`: default-centred level effects (Figure 2).
- `plot_variance_groups.R`: Figure 3.
- `plot_ensemble_distribution.R`: distribution of all specifications per practice, with summary statistics.
- `shift_cover_crop_operations.R`, `switch_cover_crop_to_rye.R`, `switch_cc_termination_to_herbicide.R`: one-time edits already applied to the included schedules; kept for provenance.

## How to update levels

Edit `scenario_levels.csv`.

- Add a row to create a new level.
- Set `active` to `TRUE` when the level is available for use.
- Set `include_in_factorial` to `TRUE` when the level should be expanded into the scenario matrix.
- Leave optional levels as `include_in_factorial = FALSE` until you want them included.

Then run:

```r
source("analysis/build_scenario_metadata.R")
```

or from a terminal:

```sh
Rscript analysis/build_scenario_metadata.R
```

The script currently removes redundant conventional-baseline rows where cycling or reversion does not change management. For those rows, only the continuous conventional baseline is retained.

### Current design (2026-10-21)

Sensitivity set (`analysis_set = "sensitivity"`, 432 scenarios: 324 projects and 108 conventional references):

- Practices: no-till, reduced till, cover crop (cereal rye), and three conventional definitions run as counterfactual references with continuous management only:
  - `conv`: spring field cultivator (D491) + fall field cultivator and tandem disk (F491), the default.
  - `convplow`: spring field cultivator (D491) + fall moldboard plow (K491), from v1 `cnt2_corn_sDfK` (`exp_corn_CONVPLOW_cont.sch`).
  - `convrt`: spring row cultivator (B491) + fall sweeps and tandem disks (E491), from v1 `cnt2_corn_sBfE` (`exp_corn_CONVRT_cont.sch`). This is the same management as reduced till, so reduced till earns no credit against it.
- N rate: UAN10 (10.0 g N/m2), UAN20 (`n_obs`, 20.2 g N/m2), UAN30 (30.0 g N/m2).
- Land-use history: site, corn-soy, continuous corn, corn-soy without fertilizer.
- Cycling: continuous, conventional every 5th year, conventional every 10th year.
- DEC4 (`fix.100` passive SOM decomposition rate): 0.0022, 0.0025 (default), and 0.0048, applied to the 2020-2050 run only; every run starts from the same 2020 state. The scenario matrix's `fix_overrides` column (e.g. `DEC4=0.00220`) passes the value to the run plan, and `run_daycent_plan.R` sets it in the site copy of `fix.100` for that run and restores the library file afterwards. The default level (`dec4_def`) is left out of scenario IDs, so runs made before the DEC4 dimension keep their names.

Set-aside scenarios (`analysis_set = "set_aside"`, 1,255): the earlier N rates (0, UAN3/6/8/11/18), the no-till continuous corn history, and the other cycling and adopt-then-revert patterns, at the default DEC4. Their credits are computed against the default conventional only. The paper uses the sensitivity set only.


## Where to document schedule files

Use `analysis/schedule_registry.csv` for schedule-file provenance. Each row can document a schedule used by the run plan:

- `stage_name`: `equilibrium`, `base`, `cnt`, or `exp`.
- `run_name`: the run name from `daycent_run_plan.csv`.
- `scenario_id`: optional; use this for scenario-specific `exp` overrides.
- `schedule_file`: the schedule file the runner should use.
- `source_schedule_file`: where the schedule came from, if it was copied, renamed, or adapted.
- `schedule_description`, `schedule_origin`, `schedule_notes`: human-readable provenance.

The run-plan builder applies active registry rows after creating convention-based paths. This means you can either rename schedules to the convention or point directly to existing files such as `sites/enfarm/v1schedules/cnt_cornsoy_2019.sch`. If a schedule is outside `sites/enfarm`, the runner stages a copy into the site folder before running DayCent.

The builder also checks the site `.100` file named on line 3 of each schedule. If that file is missing, the run is blocked in `daycent_run_plan.csv` until the schedule or site file is corrected.

## Build cycling schedules

Generate the 2-, 3-, 4-, 5-, 6-, 7-, 8-, and 10-year cycle templates with:

```sh
Rscript analysis/build_cycle_schedules.R
```

For an N-year cycle, years 1 through N-1 use the conservation-practice events from the v1 template; year N uses the conventional events. For CC, the conventional year also starts with the cover-crop termination events (`CULT HC` and `LAST` on day 117, with that year's `CULT D491` moved to day 118; see "Cover crop termination" below), so the rye planted in the previous year is terminated. The cycle repeats through 2050. The script writes NT, RT, and CC schedules to `sites/enfarm/v2schedules/` and refuses to overwrite an existing target file.

The generated cycle levels and registry entries are enabled for observed N, site-specific historic land use, and observed weather. Other N-rate, historic-land-use, or weather combinations need corresponding management schedules and registry mappings before they are runnable.

## Cover crop timing after harvest

Every cover crop year harvests corn on day 282, runs the fall field cultivator and tandem disk (`CULT F491`) on day 283, and plants the cover crop (`CROP`, `PLTM`; barley `BAR` when this script was written, now cereal rye `CCRYE`, see below) on day 284:

```sh
Rscript analysis/shift_cover_crop_operations.R
```

The fall field cultivator and tandem disk pass used to be on the harvest day. DayCent applies same-day cultivation before harvest (the manual: events on the same day "can be in any order"), so that pass moved about 25% of the live corn, grain included, into litter and soil before harvest: cover crop corn grain was 0.753 x conventional in 2020, before any cover crop had grown, and that buried grain inflated the cover crop SOC credit. The script edits every schedule that plants `BAR` (v2schedules, the staged copies in `sites/enfarm/`, and the v1 templates read by `build_cycle_schedules.R`; archive folders are unchanged). Conventional years inside cycling and reversion schedules (field cultivator and tandem disk on day 297) are not changed. Running it again changes nothing.

## Cereal rye cover crop

The cover crop is cereal rye (`CCRYE`), planted on day 284 and growing through winter and spring until termination (originally `CULT CSG` on day 127, the day before corn planting; now herbicide on day 117, see "Cover crop termination" below):

```sh
Rscript analysis/switch_cover_crop_to_rye.R
```

The script replaces `CROP BAR` with `CROP CCRYE` and removes the `LAST` that followed the cover crop planting in each cover crop year (it was on day 365, which stopped growth on 31 December so the cover crop never grew in spring). Harvest, fall field cultivator and tandem disk, planting, and termination dates are unchanged, so the cover crop schedule keeps its own fall tillage date (283) rather than the conventional one (297). It edits the same files as `shift_cover_crop_operations.R`; running it again changes nothing.

`CCRYE` in `100libraryfiles/crop.100` uses the DayCent v491 "Cereal Rye for cover crop" values (105 parameters, including `PRAMX(1,2)` = 80) and fills the 40 DayCent-CABBI parameters that v491 does not have from `BAR` (photosynthesis `AMAX`/`PSNTOPT`/`GROWTHDAYS` set, `DDEMERG`, `TMXBIO`, `SFAVAIL(1)`, luxury uptake and C storage). v491's `TMPGERM`, `CAFUE`, `EMAX`, `FAVAIL(1)`, and `NPP2CS(1)` have no DayCent-CABBI slot.

In a test of the default cover crop schedule, barley reached about 1 g C/m2 of shoots; rye reached about 170 g C/m2 of shoots and 80 g C/m2 of roots by 1 May, raised soil C inputs from 667 to 894 g C/m2/yr, and lowered spring mineral N and corn grain (about 8% below conventional). `CSG` moves live shoots to standing dead but does not kill roots (`CULTRA(7)` = 0), so rye roots stay live after termination until the corn crop replaces it.

## Cover crop termination

Every cover crop schedule terminates the rye with herbicide 11 days before corn planting (day 117; corn is planted on day 128) (2026-10-21):

```sh
Rscript analysis/switch_cc_termination_to_herbicide.R
```

Wherever a year has `CULT CSG` on day 127 followed by `CULT D491` on day 128, the script writes `CULT HC` and `LAST` on day 117 and moves `D491` to day 118; corn planting and fertilizer stay on day 128. This includes the conventional year that terminates the last rye crop in cycling and reversion schedules. It edits the same files as `switch_cover_crop_to_rye.R` (the previous schedules are in `sites/enfarm/archive/cc_schedules_pre_herbicide_2026-10-21/`); running it again changes nothing.

Why the change, from daily-output tests of the default cover crop run (`sites/enfarm/v2schedules/termination_tests/`):

- `CSG` (`cult.100`) kills no roots, so about 30% of the rye roots survived the next day's `D491` and became live corn roots when `CROP C10` switched the crop. It also applies tillage-strength decomposition multipliers (`CLTEFF` 1.5/3.5/3.5/1.5, including the passive pool) on top of `D491`, and DayCent applied its standing-dead-to-litter transfer (`CULTRA(4)`) only to standing dead present before the event, so the killed shoots stayed standing until `D491`.
- `HC` moves all shoots to standing dead, kills all roots into soil litter, and has no decomposition multipliers.
- `LAST` is needed when termination is earlier than planting: without it the rye regrew from zero after the herbicide (about 13 g C/m2 of shoots by day 127), and `CROP C10` relabeled that regrowth as corn.
- `HARV CC491` (the v491 "false harvest") ended the rye crop but moved no biomass in DayCent-CABBI; the next day's `D491` buried the live shoots, so it is not used.

| Default cover crop (net of conventional, somsc, 2020-2050) | Net SOC, Mg C/ha/yr | Corn, bu/ac/yr | Mineral N end of April, kg/ha |
|---|---|---|---|
| `CSG` day 127, `D491` day 128 (previous) | 0.338 | 184.8 | 2.4 |
| `HC` day 127, `D491` day 128 | 0.346 | 182.3 | 2.5 |
| `HC` + `LAST` day 117, `D491` day 118 (current) | 0.296 | 188.9 | 5.9 |

Conventional is 202.1 bu/ac/yr with 20.5 kg/ha mineral N at the end of April. Terminating 10 days earlier than the previous day-127 termination loses the rye's fastest-growing days (shoots about 98 vs 142 g C/m2), so less residue C, and eases N immobilization before planting.

## Build fertilizer schedules

After generating or verifying the cycle templates, generate the explicit UAN/no-fertilizer schedules and supplemental scenarios:

```sh
Rscript analysis/build_fertilizer_schedules.R
```

The script generates rate variants for CONV continuous management and for NT, RT, and CC continuous, every periodic cycle, and adopt-then-revert schedules. It reuses each `.sch` across all HLU scenarios because HLU is represented by the preceding `cnt` run. It writes or verifies 222 unique schedule files and creates 1,110 supplemental scenario rows: six explicit rates x five HLUs (`hlu_site`, `hlu_cs`, `hlu_cc`, `hlu_ntc`, `hlu_cs0n`) x the applicable management patterns, with conventional management limited to continuous. Before generating variants, the script checks every base template: each block's `Repeats # years` must equal its highest event year (otherwise DayCent leaves the unlisted years fallow), and every block after the first must use weather choice `C` (`F` restarts the weather file, misaligning weather against the single-block conventional control). The CC adopt-then-revert templates use a one-year reversion block with the `CULT CSG` termination event, followed by the repeating conventional block.

The UAN levels map by code to nominal concentrations UAN3/6/8/11/18 = 3/6/8/11/18 g N/m2; their actual `fert.100` parameter values are 2.8/5.6/8.4/11.2/18.0 g N/m2. The no-fertilizer schedules omit the FERT event. These earlier levels are set-aside scenarios (`set_aside_scenarios.csv`). The script also builds UAN10 and UAN30 variants (10.0 and 30.0 g N/m2) of the current-design templates: the three conventional definitions and NT/RT/CC continuous, and NT/RT/CC 5- and 10-year cycles. `build_scenario_metadata.R` maps each scenario to the shared schedule path. It no longer writes a supplemental scenario list.

Run `build_scenario_metadata.R` and `build_daycent_run_plan.R` before using the plan runner. The current scenario matrix has 1,295 scenarios: the 1,110 explicit-rate scenarios plus 185 `n_obs` (UAN20) scenarios. `n_obs` maps to the unsuffixed base schedules, which apply UAN20. All 1,295 scenarios have schedules and completed runs.

### Corn-soy history without fertilizer (`hlu_cs0n`)

`sites/enfarm/cnt_cornsoy0N_2019.sch` is `cnt_cornsoy_2019.sch` (2008-2019) with its six FERT events removed. It runs from `base.bin` as `cnt_hlu_cs0n_w_obs` and gives the lowest start-of-2020 somsc of the histories (34.8 Mg C/ha, vs 36.5 site-specific, 37.2 corn-soy, 46.6 continuous corn, 48.3 no-till continuous corn).

## How to build and run the DayCent plan

Build the staged run plan:

```r
source("analysis/build_daycent_run_plan.R")
```

or:

```sh
Rscript analysis/build_daycent_run_plan.R
```

The run plan has one row per DayCent run stage. The default/basic chain keeps the calibrated model structure:

```text
eq.bin -> base.bin -> cnt.bin -> exp scenario
```

`eq` is the equilibrium spinup, `base` is the calibrated 1848-2007 historic land-use period, and `cnt` is the calibrated 2008-2019 contemporary historical period. Alternative historic land-use assumptions branch in the `cnt` period only, using new `cnt_*.sch` files that build from `base.bin`. Experimental 2020-2050 rows build from either the existing `cnt.bin` or the alternative `cnt_*.bin` created for that scenario.

Preview runnable rows without launching DayCent:

```sh
Rscript analysis/run_daycent_plan.R
```

Run selected rows only after reviewing the dry run:

```sh
Rscript analysis/run_daycent_plan.R --execute --stage=exp --limit=1
```

Existing `.bin` files are skipped by default. Add `--force` only when you intentionally want to replace an existing bin file.

## How to extract bin pools

`somtc`, `totc`, `totsysc`, and the N volatilization accumulators are not in the DayCent CSV outputs, but every `.bin` stores them. After running DayCent, run:

```sh
Rscript analysis/extract_bin_pools.R
```

The script runs `list100` on each exp-stage bin and writes `<run_name>_binpools.csv` (one start-of-year snapshot per year) into the run's output folder. Runs whose `.bin` is newer than their binpools file are re-extracted, so rerunning DayCent with `--force` does not leave stale values. Extraction takes about 0.3 s per run.

## How to compile outputs

Run:

```r
source("analysis/compile_outputs.R")
```

or from a terminal:

```sh
Rscript analysis/compile_outputs.R
```

The compiler writes:

- `outputs/summary/daycent_annual_summary.csv`
- `outputs/summary/daycent_output_inventory.csv`

The annual summary includes derived carbon pools, Mg C/ha conversions, Mg CO2e/ha conversions, harvested carbon when available, and N2O CO2e when N flux output is available.

When binpools files exist, the summary also includes `somtc`, `totc`, and `totsysc` stocks, annual N volatilization (`annual_volatilized_n_g_m2`, from the cumulative `volgma + volexa + volpla` accumulators), and annual NO3 leaching (`annual_no3_leach_n_g_m2`, from `nflux`). All stocks are start-of-year snapshots. Because `totc` is DayCent's running annual minimum, its start-of-year value is the previous calendar year's minimum.

## How to calculate credit values

Edit `accounting_options.csv` to add, remove, or deactivate options, then run:

```sh
Rscript analysis/calculate_credit_values.R
```

The script crosses the active options into `accounting_rules.csv` and writes `outputs/summary/accounting_results.csv`, with one row per project scenario (NT, RT, CC) x rule. The current options give 180 rules and 144,720 rows (about 32 MB: 58,320 for the 324 sensitivity-set projects and 86,400 for the 1,224 set-aside projects; numbers are stored to 6 significant digits and `rule_id`/`soil_depth_cm` are kept only in `accounting_rules.csv` to stay under GitHub's 100 MB file limit):

- Carbon pools (2026-10-24, used by every analysis): slow + passive SOM C (`som2c(2) + som3c`), all soil organic C (`somsc`, the default), all soil C including belowground structural and metabolic litter (`somtc`), minimum annual total non-living C (`totc`), and total system C (`totsysc`). Soil + surface SOM C (`som1c(1) + som1c(2) + som2c(1) + som2c(2) + som3c`) is listed in `accounting_options.csv` but inactive.
- Horizons: 10, 20, and 30 years from 2020 (2026-10-23: 2 and 5 years set inactive). A 50-year option is listed but inactive until the exp runs are extended to 2070.
- Counterfactuals: one per conventional definition, each run continuously at the project's N rate, history, weather, and DEC4: `cf_conv` (field cultivator + fall field cultivator and tandem disk, the default), `cf_convplow` (field cultivator + fall moldboard plow), and `cf_convrt` (row cultivator + fall sweeps/tandem disks, the same management as reduced till). The option's `value` column in `accounting_options.csv` names the conventional practice. Set-aside projects are credited against `cf_conv` only (the alternative conventionals were not run for them). The earlier options (b) (conventional at UAN20) and (c) (no counterfactual) were removed.
- N2O: not included (SOC only) or included as direct N2O at GWP 265 (IPCC AR5, the GWP used for UNFCCC/Paris Agreement reporting). Options for GWP 298 (AR4), 273 (AR6), and direct + indirect N2O remain in `accounting_options.csv` but are inactive.
- Functional unit: per area (credit per hectare) or per bushel of corn, as carbon-intensity crediting like FD-CIC and fuel CI scoring. For per-bushel crediting each system's emissions over the horizon (E = -stock change x 44/12, plus N2O when the N2O option counts it) are divided by its own corn bushels over the same years, and the credit per bushel is the counterfactual's intensity minus the project's (`net_credit_kg_co2e_bu`, kg CO2e/bu). So that both units share one scale in the decomposition, tornado, and other summaries, the per-area columns hold its area-equivalent, credit per bushel x project bushels/ha/yr. This equals the area credit plus E_counterfactual x (project bushels / counterfactual bushels - 1), so it differs from the area credit only when the practice changes yield. With no counterfactual (c) the two units are identical. For per-area rows, `net_credit_kg_co2e_bu` is the area credit over project bushels (a reporting conversion only). The heatmap, reversion, and fertilizer figures use per-area rows.

Bushels: DayCent grain C (`annual_cgrain`, g C/m2, dry matter) / 0.435 g C/g (Gescha et al., 2010, as in `RunDaycent.Rmd`) / 21.46 kg dry grain per bushel. A 56 lb (25.40 kg) bushel is at 15.5% moisture, so it holds 25.40 x 0.845 = 21.46 kg dry matter; `RunDaycent.Rmd` divided dry grain by 25.4 kg, which counts about 15% fewer bushels and overstates per-bushel values by about 18%. Bushels sum the same model years as N2O (2020 through the year before the endpoint). `corn_bu_ha_yr_project` and `corn_bu_ha_yr_counterfactual` report the mean yields.

All credited amounts are annualized (Mg CO2e/ha/yr = total over the horizon / horizon years) and reported at 20 cm: DayCent's soil pools cover 0-20 cm (`fix.100` EDEPTH = 0.20 m). `totc` adds surface litter and surface SOM, and `totsysc` also adds live plant C. Stock change runs from 2020 to the endpoint year; N2O sums full model years 2020 through the year before the endpoint. Direct N2O is DayCent nitrification plus denitrification N2O. Indirect N2O uses the IPCC 2019 Refinement Tier 1 factors (Vol. 4, Ch. 11, Table 11.3): DayCent NO3 leaching x EF5 (0.011), plus applied fertilizer N x Frac_GASF (0.11) x EF4 (0.010). Volatilization uses the Tier 1 fraction because this DayCent-CABBI build does not simulate fertilizer NH3 volatilization (`volgma` and `volexa` are zero; only plant volatilization at harvest, `volpla`, is nonzero).

Result columns: `soc_benefit_mg_co2e_ha_yr` (project minus counterfactual stock change), `n2o_increase_mg_co2e_ha_yr` (project minus counterfactual N2O; positive means more emissions), `net_credit_mg_co2e_ha_yr` (SOC benefit minus N2O increase), and `net_credit_total_mg_co2e_ha` for reference. Adding a counterfactual option requires a matching definition in `calculate_credit_values.R`; the script stops on unknown counterfactual IDs.

## Decompose variance across the specification ensemble

After running `calculate_credit_values.R`, run:

```sh
Rscript analysis/specification_variance_decomposition.R
```

This is an ANOVA-style variance decomposition of a deterministic specification ensemble, not an inferential ANOVA of independent observations. Each practice is decomposed separately; practice is not a factor, because the difference between practices is not uncertainty in a practice's credit. Each specification is one combination of four biophysical inputs (N rate, historic land use, cycling/reversion, DEC4) and five accounting choices (carbon pool, horizon, counterfactual, N2O treatment, functional unit), and its annualized net credit (`net_credit_mg_co2e_ha_yr`) is a deterministic DayCent-based result with no sampling error. F statistics and p-values are therefore not reported.

**Estimand.** The decomposition targets the variance of net credit when every enumerated specification is weighted equally, that is, under a discrete uniform distribution over the specification grid, and the share of that variance attributable to each factor and interaction. Shares therefore depend on which levels are enumerated (for example, how many carbon pools or horizons are listed) and on treating each level as equally plausible; they describe this grid, not a probability-weighted population of real-world outcomes.

**Method.** Each practice's ensemble is its part of the sensitivity set: 3 N rates x 4 histories x 3 cycling levels x 3 DEC4 levels x 5 pools x 3 horizons x 3 counterfactuals x 2 N2O options x 2 functional units = 19,440 specifications (58,320 across the three practices). The grid is a balanced full factorial with one value per cell, so each term's sum of squares is computed exactly from marginal means (an inclusion-exclusion sum over the term's factor subsets) instead of fitting a large linear model. Terms run from main effects through three-way interactions; four-way and higher interactions form the remainder. The calculation was checked against `aov()` on a balanced subset (all sums of squares agree to about 1e-12). Outputs:

- `outputs/summary/specification_variance_decomposition.csv`: one row per practice (`ensemble`) and term, with df, sum of squares, variance contribution (sum of squares / number of specifications, i.e. the term's contribution to the uniform-weighted variance), and share of ensemble variance; each row records the weighting and the number of specifications
- `outputs/summary/specification_variance_by_group.csv`: share of each practice's ensemble variance by group (biophysical, accounting, biophysical x accounting, remainder)
- `outputs/summary/specification_variance_by_practice.png`: top 15 terms by share of each practice's ensemble variance

## Paper figures and summary numbers

After running `calculate_credit_values.R` and `summarize_default_results.R`, run:

```sh
Rscript analysis/specification_variance_decomposition.R   # variance shares (Figure 3, SI)
Rscript analysis/plot_default_soc_net.R                   # Figure 1
Rscript analysis/plot_tornado.R                           # Figure 2
Rscript analysis/plot_variance_groups.R                   # Figure 3
Rscript analysis/plot_ensemble_distribution.R             # ensemble medians, central 95%, share below zero
```

Figure 2 is `outputs/summary/tornado_full_sensitivity_default_pub_horizontal_ticks.png`. For each factor and every combination of the other factors, the change at a level is the net benefit at that level minus the net benefit at the factor's default level; the median of those changes is the level's value (white tick), and each bar spans the lowest to highest level median. `plot_tornado.R` also writes exploratory versions of the tornado (one-at-a-time sweeps, mean-centred and median-centred variants); only the file above is used in the paper.
