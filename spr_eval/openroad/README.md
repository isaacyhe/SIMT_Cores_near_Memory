# OpenROAD + ASAP7 Setup

## Prerequisites

### 1. Install OpenROAD

```bash
# Option A: Using package manager (Ubuntu 22.04+)
sudo apt install openroad

# Option B: Build from source
git clone --recursive https://github.com/The-OpenROAD-Project/OpenROAD.git
cd OpenROAD
./etc/DependencyInstaller.sh
mkdir build && cd build
cmake ..
make -j$(nproc)
sudo make install
```

### 2. Install ASAP7 PDK

```bash
# Clone ASAP7
git clone https://github.com/The-OpenROAD-Project/asap7.git
export ASAP7_DIR=$(pwd)/asap7

# Or download from ASU
# https://asap.asu.edu/
```

### 3. Set Environment Variables

Add to your `.bashrc` or run before executing:

```bash
export ASAP7_DIR=/path/to/asap7
export PATH=$PATH:/path/to/openroad/bin
```

## ASAP7 PDK Files

The flow expects these files in `$ASAP7_DIR`:

```
asap7/
├── asap7_tech_1x_201209.lef           # Technology LEF
├── asap7sc7p5t_28_R_1x_220121a.lef    # Standard cell LEF
├── asap7sc7p5t_SEQ_RVT_TT_nldm_*.lib  # Sequential cells
├── asap7sc7p5t_OA_RVT_TT_nldm_*.lib   # OA cells
├── asap7sc7p5t_INVBUF_RVT_TT_*.lib    # Inverters/Buffers
└── asap7sc7p5t_AO_RVT_TT_nldm_*.lib   # AO cells
```

## Flow Configuration

Edit `setup.tcl` to adjust:
- `CLK_PERIOD`: Target clock period (ns)
- `CORE_UTILIZATION`: Die utilization (0.0-1.0)
- `PLACE_DENSITY`: Placement density
- Library corners (TT, FF, SS)

## Running the Flow

```bash
# Set ASAP7 path
export ASAP7_DIR=/path/to/asap7

# Run SPR
cd spr_eval
./scripts/run_spr.sh baseline

# Or run all
./scripts/run_all.sh --parallel 4
```

## Expected Output

```
results/<config>/
├── area_report.txt      # Cell count, die area
├── timing_setup.txt     # Setup slack
├── timing_hold.txt      # Hold slack
├── timing_tns.txt       # Total negative slack
├── power_report.txt     # Dynamic + leakage power
├── drc_report.txt       # Design rule violations
├── final.def            # Final DEF
└── final.v              # Final netlist
```

## Alternative: OpenROAD-flow-scripts

For a more complete flow, consider using:
https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts

```bash
git clone --recursive https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts
cd OpenROAD-flow-scripts
./build_openroad.sh
```
