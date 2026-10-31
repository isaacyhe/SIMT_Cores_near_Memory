# Caches near the DRAM banks: per-run energy of a Vortex GPU in processing-near-memory

This repository holds the hardware, simulation flow, physical-design recipes and data behind our study of cache design for a GPU
core placed near HBM2 DRAM banks (Vortex Workshop talk at MICRO 2026, and the IEEE Computer Architecture Letters submission).
Every number comes from cycle-accurate simulation of the real RTL (Vortex with FPnew floating point and the RTL integer
multiplier and divider) and from routed ASAP7 layouts.

## What is in the study

- 53 GPU configurations: cache capacity, associativity and presence, warp count, SIMT width (up to 32 lanes x 32 warps),
  local memory, and software-emulated division.
- Memory proximity from off-chip (r = 1.0) through the logic die (r = 0.4) to beside the bank (r = 0.1), where r scales the
  DRAM clock relative to the core.
- 24 OpenCL benchmarks at 16x inputs, one run per (configuration, ratio, benchmark).
- Per-run energy: core clock and leakage from each routed layout's power floor, core switching from per-run RTL activity
  propagated through the routed netlist, SRAM from calibrated pCACTI tables, and DRAM from per-command and per-burst HBM2
  energies plus background and refresh over the physical DRAM time.

## Layout

| Path | Contents |
|---|---|
| `vortex/` | Vortex GPU (Apache-2.0, see `vortex/LICENSE`) with the changes used here: FPnew, activity counters, byte-enable FakeRAM, DRAM command statistics and a physical-time shadow DRAM model, gate-level and calibration harnesses (`sim/gatesim_fpnew`, `sim/rtlsim_cal`) |
| `eval_perf_swemu/scripts/` | Simulation runners and acceptance checks (`run_energy_wave.sh`, `check_energy_wave.sh`, `row_identities.py`) |
| `eval_perf_swemu/configs/` | One `config.mk` per configuration |
| `eval_perf_swemu/benchmarks_modified/` | Benchmark sources with software-emulated division for the soft-math configurations |
| `eval_perf_swemu/jobs_*` | The job lists of every simulation group (one file per configuration and ratio) |
| `pnr/designs/asap7/` | OpenROAD-flow-scripts recipes of every routed layout (`config.mk`, `constraint.sdc`, `pdn.tcl`) |
| `spr_eval/` | Per-configuration RTL overrides used to generate the synthesis netlists |
| `ieee_cal/analysis/` | Energy pipeline: power floors, SRAM tables, DRAM constants, activity model, core switching, sign-off clocks, calibration scripts |
| `ieee_cal/data/` | Results: `energy.csv` (per-run energy, every part), `runs.csv` and `summary.csv` (cycles) |

## Main results files

- `ieee_cal/data/energy.csv`: one row per run with every energy part (`e_core_clock_J`, `e_core_leak_J`, `e_core_dyn_J`,
  `e_sram_dyn_J`, `e_sram_leak_J`, `e_dram_cmd_J`, `e_dram_io_J`, `e_dram_bg_J`, `e_total_J`), the DRAM tier, the nominal
  memory ratio (`r_nominal`) and a DRAM-backlog flag (`dram_lag_flag`).
- `ieee_cal/analysis/floors_vddonly.tsv`: per-layout clock and leakage power floors at each layout's sign-off clock
  (`ieee_cal/analysis/signoff.tsv`).
- `ieee_cal/analysis/core_dyn.tsv`: per-run core switching energy.

## Status of the data

- Core switching energy (`e_core_dyn_J`) is an interim estimate (`core_dyn_calibrated = 0`). A gate-level calibration against
  netlist simulation is in progress; it will replace these values. Core switching is a median 5.5% of a run's energy.
- The wide configurations (16 to 32 lanes, 16 to 32 warps) are being added as their layouts are signed off. Designs that do not
  close timing at 500 MHz run at a slower clock from a fixed grid (400, 333, 250, 200, 166.67 or 100 MHz); their memory ratios
  are scaled so a DRAM tick keeps its nominal length.
- Raw per-run simulator outputs (counters and DRAM statistics, about 650 MB) are not in this repository.

## Reproducing

The flow expects the checkout at `/home/he/workspace/GPU_and_PNM`: the job lists name benchmark inputs by absolute path and the
runners check them exactly. Simulations need Verilator and the Vortex RISC-V toolchain and PoCL; layouts need
OpenROAD-flow-scripts with the ASAP7 platform and the byte-enable FakeRAM macros. The cluster job scripts take the site's paths
from `CLOUD_ROOT`, `CLOUD_HOST`, `CLOUD_USER`, `CLOUD_FS` and `CLOUD_QUOTA_PROJECT`.

- One simulation group: `eval_perf_swemu/scripts/run_energy_wave.sh eval_perf_swemu/jobs_wave1/<group>.txt 8`, then
  `check_energy_wave.sh` on the same file.
- Energy table: `python3 ieee_cal/analysis/energy.py <results_root> ...` writes `ieee_cal/data/energy.csv`.

## License

Apache License 2.0 (`LICENSE`), as Vortex. Bundled third-party components keep their own licenses (`NOTICE`): CVFPU
(Solderpad 0.51 and Apache-2.0), Ramulator 2.0 (MIT, with this study's DRAM command statistics in
`vortex/third_party/ramulator_local_changes.patch`), Berkeley SoftFloat 3 (BSD-3-Clause). The ASAP7 PDK and FakeRAM macro
views are not included.
