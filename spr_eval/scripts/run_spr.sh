#!/bin/bash
# Run SPR flow for a single Vortex configuration
# Usage: ./run_spr.sh <config_name> [--synth-only]
# Example: ./run_spr.sh baseline
# Example: ./run_spr.sh baseline --synth-only  (Yosys only, skip OpenROAD)

set -e

CONFIG_NAME=${1:-baseline}
SYNTH_ONLY=0

# Parse options
for arg in "$@"; do
    case $arg in
        --synth-only)
            SYNTH_ONLY=1
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VORTEX_ROOT="$(dirname "$PROJECT_ROOT")/vortex"
OPENROAD_DIR="$PROJECT_ROOT/openroad"

CONFIG_DIR="$PROJECT_ROOT/configs/$CONFIG_NAME"
RESULTS_DIR="$PROJECT_ROOT/results/$CONFIG_NAME"
LOG_DIR="$PROJECT_ROOT/logs"
BUILD_DIR="$PROJECT_ROOT/build/$CONFIG_NAME"

# Validate config exists
if [ ! -d "$CONFIG_DIR" ]; then
    echo "Error: Configuration '$CONFIG_NAME' not found in $PROJECT_ROOT/configs/"
    echo "Available configs:"
    ls "$PROJECT_ROOT/configs/"
    exit 1
fi

echo "=========================================="
echo "SPR Flow for: $CONFIG_NAME"
echo "Started: $(date)"
echo "Mode: $([ $SYNTH_ONLY -eq 1 ] && echo 'Synthesis Only' || echo 'Full P&R')"
echo "=========================================="

# Create output directories
mkdir -p "$RESULTS_DIR"
mkdir -p "$LOG_DIR"
mkdir -p "$BUILD_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOG_DIR/${CONFIG_NAME}_${TIMESTAMP}.log"

echo "Log file: $LOG_FILE"
echo "Build dir: $BUILD_DIR"

# Read config defines from override file
CONFIG_DEFINES=""
echo ""
echo "Configuration defines:"
echo "----------------------"
if [ -f "$CONFIG_DIR/VX_config_override.vh" ]; then
    while IFS= read -r line; do
        if [[ "$line" =~ ^\`define[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)([[:space:]]+(.+))?$ ]]; then
            def_name="${BASH_REMATCH[1]}"
            def_value="${BASH_REMATCH[3]}"
            if [ -n "$def_value" ]; then
                CONFIG_DEFINES="$CONFIG_DEFINES -D${def_name}=${def_value}"
                echo "  -D${def_name}=${def_value}"
            else
                CONFIG_DEFINES="$CONFIG_DEFINES -D${def_name}"
                echo "  -D${def_name}"
            fi
        fi
    done < "$CONFIG_DIR/VX_config_override.vh"
fi
[ -z "$CONFIG_DEFINES" ] && echo "  (none - baseline)"

echo ""
echo "=========================================="
echo "Step 1: Generate sources (sv2v)"
echo "=========================================="

cd "$BUILD_DIR"

# Build CFLAGS for synthesis
CFLAGS="-DSYNTHESIS -DYOSYS -DXLEN_32 $CONFIG_DEFINES"
CFLAGS="$CFLAGS -I$VORTEX_ROOT/hw/rtl -I$VORTEX_ROOT/hw/rtl/libs"
CFLAGS="$CFLAGS -I$VORTEX_ROOT/hw/rtl/interfaces -I$VORTEX_ROOT/hw/rtl/core"
CFLAGS="$CFLAGS -I$VORTEX_ROOT/hw/rtl/mem -I$VORTEX_ROOT/hw/rtl/cache"
CFLAGS="$CFLAGS -I$VORTEX_ROOT/hw/rtl/fpu"

echo "CFLAGS: $CFLAGS" >> "$LOG_FILE"

# Generate source list (with preprocessing)
echo "Generating source list..."
mkdir -p src
$VORTEX_ROOT/hw/scripts/gen_sources.sh -P $CFLAGS -Csrc -Osources.txt >> "$LOG_FILE" 2>&1

# Convert SystemVerilog to Verilog
echo "Converting SystemVerilog to Verilog..."
$VORTEX_ROOT/hw/scripts/sv2v.sh -tVortex -Isrc -oproject.v >> "$LOG_FILE" 2>&1

if [ ! -f "project.v" ]; then
    echo "ERROR: sv2v conversion failed!"
    exit 1
fi
echo "Generated: project.v ($(wc -l < project.v) lines)"

echo ""
echo "=========================================="
echo "Step 2: Yosys Synthesis"
echo "=========================================="

# Check if ASAP7 is available for technology mapping
ASAP7_LIB=""
if [ -n "$ASAP7_DIR" ] && [ -f "$ASAP7_DIR/asap7sc7p5t_28/LIB/NLDM/asap7sc7p5t_SEQ_RVT_TT_nldm_220123.lib" ]; then
    ASAP7_LIB="$ASAP7_DIR/asap7sc7p5t_28/LIB/NLDM/asap7sc7p5t_SEQ_RVT_TT_nldm_220123.lib"
    echo "Using ASAP7 library for synthesis"
fi

# Create Yosys script with ABC technology mapping
# Note: Use SIMPLE library for combinational logic (has AND, OR, NAND, NOR, etc.)
# INVBUF only has inverters/buffers which ABC rejects as too few cells
cat > synth.ys << YOSYS_EOF
# Read design
read_verilog -defer -nolatches project.v

# Synthesize with flatten
synth -top Vortex -flatten -noabc

# Map FFs to ASAP7 sequential cells
dfflibmap -liberty $ASAP7_DIR/asap7sc7p5t_28/LIB/NLDM/asap7sc7p5t_SEQ_RVT_TT_nldm_220123.lib

# Map combinational logic to ASAP7 cells using SIMPLE library (has basic gates)
abc -liberty $ASAP7_DIR/asap7sc7p5t_28/LIB/NLDM/asap7sc7p5t_SIMPLE_RVT_TT_nldm_211120.lib

# Clean up
opt_clean

# Write output
write_verilog -noattr -noexpr synth.v

# Statistics
stat
YOSYS_EOF

echo "Running Yosys synthesis (this may take a while)..."
yosys -l yosys.log -s synth.ys >> "$LOG_FILE" 2>&1

if [ ! -f "yosys.log" ]; then
    echo "ERROR: Yosys synthesis failed!"
    exit 1
fi

if grep -q "^Error:" yosys.log; then
    echo "ERROR: Yosys reported errors!"
    grep "^Error:" yosys.log
    exit 1
fi

# Check synth.v - ABC should produce clean output
if [ -f "synth.v" ]; then
    echo "Generated: synth.v ($(wc -l < synth.v) lines)"
else
    echo "WARNING: synth.v not found"
fi

# Parse Yosys statistics
CELLS=$(grep "Number of cells:" yosys.log | tail -1 | awk '{print $NF}')
WIRES=$(grep "Number of wires:" yosys.log | tail -1 | awk '{print $NF}')
WIRE_BITS=$(grep "Number of wire bits:" yosys.log | tail -1 | awk '{print $NF}')
MEMORIES=$(grep "Number of memories:" yosys.log | tail -1 | awk '{print $NF}')
MEM_BITS=$(grep "Number of memory bits:" yosys.log | tail -1 | awk '{print $NF}')

echo "Yosys Results:"
echo "  Total Cells:      $CELLS"
echo "  Total Wires:      $WIRES"
echo "  Wire Bits:        $WIRE_BITS"
echo "  Memories:         $MEMORIES"
echo "  Memory Bits:      $MEM_BITS"

cp yosys.log "$RESULTS_DIR/"
cp synth.v "$RESULTS_DIR/" 2>/dev/null || true

# Stop here if synthesis only
if [ $SYNTH_ONLY -eq 1 ]; then
    echo ""
    echo "Synthesis-only mode: Skipping OpenROAD P&R"

    cat > "$RESULTS_DIR/results.txt" << RESULTS_EOF
Configuration: $CONFIG_NAME
Timestamp: $TIMESTAMP
Status: SYNTH_COMPLETE
Mode: Synthesis Only

=== Yosys Synthesis Results ===
Total Cells:      $CELLS
Total Wires:      $WIRES
Wire Bits:        $WIRE_BITS
Memories:         $MEMORIES
Memory Bits:      $MEM_BITS

=== Config Defines ===
$CONFIG_DEFINES
RESULTS_EOF

    echo ""
    echo "=========================================="
    echo "Synthesis Completed: $CONFIG_NAME"
    echo "Finished: $(date)"
    echo "=========================================="
    exit 0
fi

echo ""
echo "=========================================="
echo "Step 3: OpenROAD Place & Route"
echo "=========================================="

# Check for ASAP7 PDK
if [ -z "$ASAP7_DIR" ]; then
    echo "WARNING: ASAP7_DIR not set. Skipping OpenROAD P&R."
    echo "Set ASAP7_DIR and re-run for full P&R flow."
    echo "See: openroad/README.md for setup instructions."

    cat > "$RESULTS_DIR/results.txt" << RESULTS_EOF
Configuration: $CONFIG_NAME
Timestamp: $TIMESTAMP
Status: SYNTH_COMPLETE (P&R skipped - ASAP7_DIR not set)

=== Yosys Synthesis Results ===
Total Cells:      $CELLS
Total Wires:      $WIRES
Wire Bits:        $WIRE_BITS
Memories:         $MEMORIES
Memory Bits:      $MEM_BITS

=== Config Defines ===
$CONFIG_DEFINES
RESULTS_EOF

    exit 0
fi

# Check for OpenROAD
if ! command -v openroad &> /dev/null; then
    echo "WARNING: OpenROAD not found in PATH. Skipping P&R."
    exit 0
fi

# Export environment for OpenROAD
export CONFIG_NAME
export BUILD_DIR
export RESULTS_DIR
export OPENROAD_DIR
export ASAP7_DIR

echo "Running OpenROAD flow..."
openroad -exit "$OPENROAD_DIR/flow.tcl" >> "$LOG_FILE" 2>&1

# Parse OpenROAD results
if [ -f "$RESULTS_DIR/area_report.txt" ]; then
    AREA=$(grep "Design area" "$RESULTS_DIR/area_report.txt" | awk '{print $3}')
    echo "  Design Area: $AREA um²"
fi

if [ -f "$RESULTS_DIR/timing_setup.txt" ]; then
    SLACK=$(grep "worst slack" "$RESULTS_DIR/timing_setup.txt" | awk '{print $NF}')
    echo "  Worst Slack: $SLACK ns"
fi

if [ -f "$RESULTS_DIR/power_report.txt" ]; then
    POWER=$(grep "Total" "$RESULTS_DIR/power_report.txt" | tail -1 | awk '{print $2}')
    echo "  Total Power: $POWER"
fi

# Final results
cat > "$RESULTS_DIR/results.txt" << RESULTS_EOF
Configuration: $CONFIG_NAME
Timestamp: $TIMESTAMP
Status: COMPLETED
Mode: Full P&R

=== Yosys Synthesis Results ===
Total Cells:      $CELLS
Total Wires:      $WIRES
Wire Bits:        $WIRE_BITS
Memories:         $MEMORIES
Memory Bits:      $MEM_BITS

=== OpenROAD P&R Results ===
Design Area:      $AREA um²
Worst Slack:      $SLACK ns
Total Power:      $POWER

=== Config Defines ===
$CONFIG_DEFINES

=== Build Info ===
Vortex Root: $VORTEX_ROOT
Build Dir: $BUILD_DIR
ASAP7 Dir: $ASAP7_DIR
RESULTS_EOF

echo ""
echo "Results saved to: $RESULTS_DIR/"
echo ""
echo "=========================================="
echo "SPR Completed: $CONFIG_NAME"
echo "Finished: $(date)"
echo "=========================================="
