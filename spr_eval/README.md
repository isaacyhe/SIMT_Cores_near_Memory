# Vortex PNM SPR Evaluation

ASIC Synthesis, Place & Route evaluation for PNM core design exploration.

## Tool Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     SYNTHESIS PHASE                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Vortex RTL (SystemVerilog)                                     │
│       hw/rtl/*.sv                                               │
│            │                                                     │
│            ▼                                                     │
│  ┌─────────────────┐                                            │
│  │      sv2v       │  SystemVerilog → Verilog-2001              │
│  │   (converter)   │  Handles: interfaces, structs, generate    │
│  └────────┬────────┘                                            │
│           │                                                      │
│           ▼                                                     │
│      project.v (Verilog-2001)                                   │
│           │                                                      │
│           ▼                                                     │
│  ┌─────────────────┐                                            │
│  │      Yosys      │                                            │
│  │  ┌───────────┐  │                                            │
│  │  │read_verilog│ │  Parse Verilog                             │
│  │  │   synth   │  │  Elaborate + Optimize + Flatten            │
│  │  │ dfflibmap │  │  Map FFs → ASAP7 sequential cells          │
│  │  │    abc    │  │  Map logic → ASAP7 combinational cells     │
│  │  └───────────┘  │  (uses Liberty timing files)               │
│  └────────┬────────┘                                            │
│           │                                                      │
│           ▼                                                     │
│       synth.v (ASAP7 gate-level netlist)                        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                    PLACE & ROUTE PHASE                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────┐                                            │
│  │    OpenROAD     │                                            │
│  │  ┌───────────┐  │                                            │
│  │  │ read_lef  │  │  ASAP7 cell physical layouts               │
│  │  │read_liberty│ │  ASAP7 timing/power models                 │
│  │  │read_verilog│ │  Gate-level netlist (synth.v)              │
│  │  │ read_sdc  │  │  Timing constraints (500 MHz)              │
│  │  │ floorplan │  │  Initialize die/core area                  │
│  │  │ placement │  │  Place cells (global + detailed)           │
│  │  │    CTS    │  │  Clock tree synthesis                      │
│  │  │  routing  │  │  Metal interconnect (global + detailed)    │
│  │  └───────────┘  │                                            │
│  └────────┬────────┘                                            │
│           │                                                      │
│           ▼                                                     │
│  ┌─────────────────┐                                            │
│  │     Reports     │                                            │
│  │  • Area (mm²)   │                                            │
│  │  • Power (mW)   │                                            │
│  │  • Timing (ns)  │                                            │
│  │  • DRC status   │                                            │
│  └─────────────────┘                                            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Tools Summary

| Stage | Tool | Input | Output |
|-------|------|-------|--------|
| SV→V | sv2v | *.sv | project.v |
| Synthesis | Yosys + ABC | project.v + Liberty | synth.v |
| P&R | OpenROAD | synth.v + LEF/Liberty | Reports |

## Technology: ASAP7 7nm PDK

| Parameter | Value |
|-----------|-------|
| Process | 7nm FinFET (predictive) |
| Vt Flavor | RVT (Regular Vt) |
| PVT Corner | TT (Typical-Typical) |
| Clock Period | 2.0 ns (500 MHz) |
| Utilization | 50% |

## Directory Structure

```
spr_eval/
├── configs/                    # Configuration variants
│   ├── baseline/              # Full Vortex GPU (reference)
│   ├── no_cache/              # L1 caches + LMEM disabled
│   ├── one_warp/              # Single warp (no scheduling)
│   ├── no_fpdiv/              # FP div/sqrt removed
│   ├── no_intdiv/             # INT div removed (M ext disabled)
│   ├── no_numeric/            # FP + INT combined
│   └── combined_pnm/          # All simplifications combined
├── openroad/                   # OpenROAD P&R configuration
│   ├── setup.tcl              # ASAP7 PDK setup
│   ├── constraints.sdc        # Timing constraints
│   ├── flow.tcl               # P&R flow script
│   └── pdn.tcl                # Power distribution network
├── scripts/                    # Automation scripts
│   ├── run_spr.sh             # Main SPR flow script
│   ├── run_all.sh             # Run all configs (parallel)
│   ├── fix_verilog.py         # Verilog syntax fixer
│   └── estimate_power_area.py # Synthesis-based estimation
├── build/                      # Build artifacts (generated)
├── results/                    # Output metrics (area, power, timing)
└── logs/                       # Run logs
```

## Configuration Summary

| Config | Define Used | What's Disabled | Expected Area Δ |
|--------|-------------|-----------------|-----------------|
| baseline | (none) | Nothing | — |
| no_cache | `L1_DISABLE`, `LMEM_DISABLE` | I-Cache, D-Cache, Local Mem | ~-20-25% |
| one_warp | `NUM_WARPS=1` | Warp scheduling | ~-5-10% |
| no_fpdiv | `EXT_F_DISABLE` | Entire FPU (F extension) | ~-15-20% |
| no_intdiv | `EXT_M_DISABLE` | MUL + DIV (M extension) | ~-5-10% |
| no_numeric | `EXT_F_DISABLE`, `EXT_M_DISABLE` | FPU + M extension | ~-20-25% |
| combined_pnm | All above | Maximum simplification | ~-40-55% |

## Prerequisites

### 1. Install Yosys

```bash
# Ubuntu/Debian
sudo apt install yosys

# Or build from source
git clone https://github.com/YosysHQ/yosys.git
cd yosys && make -j$(nproc) && sudo make install
```

### 2. Install sv2v

```bash
# Download binary release
wget https://github.com/zachjs/sv2v/releases/latest/download/sv2v-Linux.zip
unzip sv2v-Linux.zip && sudo mv sv2v /usr/local/bin/
```

### 3. Install OpenROAD

```bash
# Ubuntu 22.04+
sudo apt install openroad

# Or use OpenROAD-flow-scripts (recommended)
git clone --recursive https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts.git
```

### 4. Install ASAP7 PDK

```bash
git clone https://github.com/The-OpenROAD-Project/asap7.git
export ASAP7_DIR=$(pwd)/asap7
```

## Usage

```bash
# Set environment
export ASAP7_DIR=/path/to/asap7

# Run single configuration (full P&R)
./scripts/run_spr.sh baseline

# Run synthesis only (faster)
./scripts/run_spr.sh baseline --synth-only

# Run all configurations in parallel
./scripts/run_all.sh --parallel 4 --synth-only
```

## Synthesis-Only Estimation

When full P&R is not feasible, synthesis-based estimation provides useful metrics.

### Accuracy vs Full P&R

| Metric | Synthesis Est. | vs P&R | Notes |
|--------|---------------|--------|-------|
| Cell Area | Direct | ~100% | Exact cell count |
| Total Area | Cell only | ~70-80% | Missing routing overhead |
| Cell Power | Direct | ~95% | Accurate |
| Total Power | Cell only | ~55-70% | Missing wires, clock tree |
| **Relative Δ** | Config A vs B | **~95%** | Best for comparisons |

### Calibrated Estimation

With ONE full P&R result, calibrate all synthesis estimates:

```
k_area = Area_PR / Area_synth
k_power = Power_PR / Power_synth

Estimated_PR = Synth_result × k
```

This improves absolute accuracy to ~5-10% error.

## Output Reports

### Synthesis Only (`--synth-only`)
```
results/<config>/
├── yosys.log           # Full Yosys log
├── synth.v             # Synthesized netlist
└── results.txt         # Summary (cells, wires, memory bits)
```

### Full P&R
```
results/<config>/
├── area_report.txt     # Die area, cell count
├── timing_setup.txt    # Setup slack
├── power_report.txt    # Dynamic + leakage power
├── final.def           # Final layout (DEF)
└── final.v             # Post-route netlist
```

## Alternative: OpenROAD-flow-scripts

For production-quality P&R with better robustness:

```bash
cd OpenROAD-flow-scripts/flow
make DESIGN_CONFIG=designs/asap7/vortex/config.mk
```

## Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| Escaped identifiers (`\name`) | sv2v hierarchical names | Use ABC mapping or fix_verilog.py |
| `$_DFF_P_` not found | Generic Yosys cells | Use `dfflibmap -liberty` |
| Floorplan `-site` error | Missing site spec | Add `-site asap7sc7p5t` |
| ABC memory issues | Design complexity | Use `-fast` or more RAM |

## References

- [Vortex GPGPU](https://github.com/vortexgpgpu/vortex)
- [OpenROAD](https://github.com/The-OpenROAD-Project/OpenROAD)
- [Yosys](https://github.com/YosysHQ/yosys)
- [ASAP7 PDK](https://github.com/The-OpenROAD-Project/asap7)
- [sv2v](https://github.com/zachjs/sv2v)
