#!/bin/bash
# Run a single RTL simulation with VCD waveform capture for power estimation
# Usage: ./run_single_rtlsim_vcd.sh <config> <benchmark> [opts_override]
#
# Differences from run_single_rtlsim.sh:
#   - Builds rtlsim with DEBUG=1 (enables --trace, VCD_OUTPUT)
#   - Captures trace.vcd after each run
#   - Uses mem_ratio=1.0 only (RTL switching is independent of DRAM latency)
#   - 1x input size only (keep VCD files manageable)
#
# Output:
#   results_rtlsim_vcd/<config>/<benchmark>.vcd   (signal-level switching activity)
#   results_rtlsim_vcd/<config>/<benchmark>.txt   (perf counters)
#   results_rtlsim_vcd/<config>/<benchmark>.log   (simulation log)

set -euo pipefail

CONFIG=$1
BENCHMARK=$2
OPTS_OVERRIDE="${3:-}"

# Handle "_" placeholder for empty opts
if [ "$OPTS_OVERRIDE" = "_" ]; then
    OPTS_OVERRIDE=""
fi

if [ -z "$CONFIG" ] || [ -z "$BENCHMARK" ]; then
    echo "Usage: $0 <config> <benchmark> [opts_override]"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EVAL_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(dirname "$EVAL_DIR")"
VORTEX_DIR="$ROOT_DIR/vortex"
CONFIG_DIR="$EVAL_DIR/configs/$CONFIG"
MODIFIED_BENCH_DIR="$EVAL_DIR/benchmarks_modified"

# VCD results go to results_rtlsim_vcd/<config>/
RESULTS_DIR="$EVAL_DIR/results_rtlsim_vcd/${CONFIG}"
mkdir -p "$RESULTS_DIR"

RESULT_FILE="$RESULTS_DIR/${BENCHMARK}.txt"
LOG_FILE="$RESULTS_DIR/${BENCHMARK}.log"
VCD_FILE="$RESULTS_DIR/${BENCHMARK}.vcd"

# Check if config exists
if [ ! -d "$CONFIG_DIR" ]; then
    echo "ERROR: Config directory not found: $CONFIG_DIR"
    exit 1
fi

# Default values
MARCH="rv32imf"
MABI="ilp32f"
EXTRA_CFLAGS=""
VX_CONFIG_OVERRIDE=""
USE_MODIFIED_BENCHMARKS="0"

# Parse config.mk
if [ -f "$CONFIG_DIR/config.mk" ]; then
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue
        if [[ "$line" =~ ^[[:space:]]*MARCH[[:space:]]*=[[:space:]]*(.+)$ ]]; then
            MARCH="${BASH_REMATCH[1]}"
        fi
        if [[ "$line" =~ ^[[:space:]]*MABI[[:space:]]*=[[:space:]]*(.+)$ ]]; then
            MABI="${BASH_REMATCH[1]}"
        fi
        if [[ "$line" =~ ^[[:space:]]*CFLAGS[[:space:]]*\+=[[:space:]]*(.+)$ ]]; then
            EXTRA_CFLAGS="$EXTRA_CFLAGS ${BASH_REMATCH[1]}"
        fi
        if [[ "$line" =~ ^[[:space:]]*VX_CONFIG_OVERRIDE[[:space:]]*=[[:space:]]*(.+)$ ]]; then
            VX_CONFIG_OVERRIDE="${BASH_REMATCH[1]}"
        fi
        if [[ "$line" =~ ^[[:space:]]*USE_MODIFIED_BENCHMARKS[[:space:]]*=[[:space:]]*(.+)$ ]]; then
            USE_MODIFIED_BENCHMARKS="${BASH_REMATCH[1]}"
        fi
    done < "$CONFIG_DIR/config.mk"
fi

# Determine benchmark directory
if [ "$USE_MODIFIED_BENCHMARKS" = "1" ]; then
    BENCH_DIR="$MODIFIED_BENCH_DIR/$BENCHMARK"
else
    BENCH_DIR="$VORTEX_DIR/tests/opencl/$BENCHMARK"
fi

if [ ! -d "$BENCH_DIR" ]; then
    echo "ERROR: Benchmark directory not found: $BENCH_DIR"
    exit 1
fi

# Fixed mem_ratio=1.0 for VCD runs (RTL switching independent of DRAM latency)
MEM_RATIO="1.0"

# Build CONFIGS string for rtlsim WITH DEBUG (enables VCD)
RTLSIM_CONFIGS="-DMEM_CLOCK_RATIO=${MEM_RATIO}"
if [ -n "$VX_CONFIG_OVERRIDE" ]; then
    RTLSIM_CONFIGS="$RTLSIM_CONFIGS $VX_CONFIG_OVERRIDE"
fi

echo "[$(date +%H:%M:%S)] VCD-RTLsim: $CONFIG / $BENCHMARK"
echo "  RTLSIM_CONFIGS=$RTLSIM_CONFIGS"
echo "  USE_MODIFIED_BENCHMARKS=$USE_MODIFIED_BENCHMARKS"

START_TIME=$(date +%s.%N)

# ============================================================
# Step 1: Build rtlsim with DEBUG=1 (enables --trace, VCD_OUTPUT)
# This is done with flock to prevent parallel build races
# ============================================================

RTLSIM_VCD_BUILD_LOCK="$VORTEX_DIR/runtime/.rtlsim_vcd_build.lock"
# never while an rtlsim campaign uses runtime/librtlsim.so (energy rows check the library md5); taken here, outside the
# build subshell, so a busy lock stops this script (shared: VCD runs may overlap each other, not a campaign)
exec 8>"$VORTEX_DIR/runtime/.rtlsim_campaign.lock"
flock -sn 8 || { echo "ERROR: an rtlsim campaign holds $VORTEX_DIR/runtime/.rtlsim_campaign.lock; build in another tree or wait"; exit 1; }

(
    flock -x 200

    # Check if already built with matching config
    VCD_STAMP_FILE="$VORTEX_DIR/runtime/.rtlsim_vcd_stamp"
    EXPECTED_STAMP="VCD_${RTLSIM_CONFIGS}"
    CURRENT_STAMP=$(cat "$VCD_STAMP_FILE" 2>/dev/null)

    if [ "$CURRENT_STAMP" != "$EXPECTED_STAMP" ]; then
        echo "  Building rtlsim with DEBUG=1 (VCD enabled)..."

        # Build librtlsim.so with DEBUG=1
        if ! make -C "$VORTEX_DIR/sim/rtlsim" \
            DESTDIR="$VORTEX_DIR/runtime" \
            VORTEX_HOME="$VORTEX_DIR" \
            CONFIGS="$RTLSIM_CONFIGS" \
            DEBUG=1 PERF=1 \
            "$VORTEX_DIR/runtime/librtlsim.so" 2>"$RESULTS_DIR/${BENCHMARK}_vcd_build.log"; then
            echo "ERROR: librtlsim.so VCD build failed!"
            exit 1
        fi

        # Build libvortex-rtlsim.so
        if ! make -C "$VORTEX_DIR/runtime/rtlsim" \
            DESTDIR="$VORTEX_DIR/runtime" \
            VORTEX_HOME="$VORTEX_DIR" \
            CONFIGS="$RTLSIM_CONFIGS" \
            DEBUG=1 PERF=1 2>>"$RESULTS_DIR/${BENCHMARK}_vcd_build.log"; then
            echo "ERROR: libvortex-rtlsim.so VCD build failed!"
            exit 1
        fi

        echo "$EXPECTED_STAMP" > "$VCD_STAMP_FILE"
        echo "  VCD rtlsim build complete."
    else
        echo "  Using cached VCD rtlsim build."
    fi
) 200>"$RTLSIM_VCD_BUILD_LOCK"

# ============================================================
# Step 2: Build and run benchmark
# ============================================================
{
    echo "=== VCD RTLsim Experiment ==="
    echo "Config: $CONFIG"
    echo "Benchmark: $BENCHMARK"
    echo "RTLSIM_CONFIGS: $RTLSIM_CONFIGS"
    echo "VCD capture: enabled"
    echo "Timestamp: $(date -Iseconds)"
    echo ""
    echo "=== Simulation Output ==="

    cd "$BENCH_DIR" 2>/dev/null || exit 1

    export MARCH="$MARCH"
    export MABI="$MABI"
    export VORTEX_HOME="$VORTEX_DIR"
    export VORTEX_PROFILING=1

    TOOLDIR_ARG=""
    if [ -d "$ROOT_DIR/toolchain/pocl" ]; then
        TOOLDIR_ARG="TOOLDIR=$ROOT_DIR/toolchain"
    fi

    # Build host code (with lock)
    BUILD_STAMP_FILE=".rtlsim_vcd_build_stamp"
    EXPECTED_BUILD="${CONFIG}_vcd_${EXTRA_CFLAGS}"
    (
        flock -x 200
        CURRENT=$(cat "$BUILD_STAMP_FILE" 2>/dev/null)
        if [ "$CURRENT" != "$EXPECTED_BUILD" ] || [ ! -x "$BENCHMARK" ]; then
            make clean 2>/dev/null || true
            make MARCH="$MARCH" MABI="$MABI" $TOOLDIR_ARG 2>&1
            echo "$EXPECTED_BUILD" > "$BUILD_STAMP_FILE"
        fi
    ) 200>"$BENCH_DIR/.rtlsim_vcd_build.lock"

    # Convert __ to spaces in opts
    OPTS_EXPANDED=""
    if [ -n "$OPTS_OVERRIDE" ]; then
        OPTS_EXPANDED="${OPTS_OVERRIDE//__/ }"
    fi

    # Run with rtlsim (VCD-enabled build)
    if [ -n "$EXTRA_CFLAGS" ] && [ -n "$OPTS_OVERRIDE" ]; then
        make run-rtlsim MARCH="$MARCH" MABI="$MABI" PERF=1 $TOOLDIR_ARG CONFIGS="$EXTRA_CFLAGS" OPTS="$OPTS_EXPANDED" 2>&1 || \
        echo "ERROR: Could not run benchmark."
    elif [ -n "$EXTRA_CFLAGS" ]; then
        make run-rtlsim MARCH="$MARCH" MABI="$MABI" PERF=1 $TOOLDIR_ARG CONFIGS="$EXTRA_CFLAGS" 2>&1 || \
        echo "ERROR: Could not run benchmark."
    elif [ -n "$OPTS_OVERRIDE" ]; then
        make run-rtlsim MARCH="$MARCH" MABI="$MABI" PERF=1 $TOOLDIR_ARG OPTS="$OPTS_EXPANDED" 2>&1 || \
        echo "ERROR: Could not run benchmark."
    else
        make run-rtlsim MARCH="$MARCH" MABI="$MABI" PERF=1 $TOOLDIR_ARG 2>&1 || \
        echo "ERROR: Could not run benchmark."
    fi

} > "$LOG_FILE" 2>&1

END_TIME=$(date +%s.%N)
ELAPSED=$(echo "$END_TIME - $START_TIME" | bc 2>/dev/null || echo "0")

# ============================================================
# Step 3: Capture VCD and parse results
# ============================================================

# Move trace.vcd from benchmark dir to results
if [ -f "$BENCH_DIR/trace.vcd" ]; then
    mv "$BENCH_DIR/trace.vcd" "$VCD_FILE"
    VCD_SIZE=$(stat --format="%s" "$VCD_FILE" 2>/dev/null || echo "0")
    echo "  VCD captured: $VCD_FILE ($(( VCD_SIZE / 1024 / 1024 ))MB)"
else
    VCD_SIZE=0
    echo "  WARNING: No trace.vcd generated!"
fi

# Parse status and perf counters
STATUS="COMPLETED"
if grep -q "PASSED" "$LOG_FILE"; then STATUS="PASSED"
elif grep -q "FAILED" "$LOG_FILE"; then STATUS="FAILED"
elif grep -q "ERROR" "$LOG_FILE"; then STATUS="ERROR"
fi

CYCLES=$(grep -oP 'instrs=\d+, cycles=\K\d+' "$LOG_FILE" | tail -1)
INSTRUCTIONS=$(grep -oP 'instrs=\K\d+' "$LOG_FILE" | tail -1)

cat > "$RESULT_FILE" << EOF
config=$CONFIG
benchmark=$BENCHMARK
simulator=rtlsim_vcd
mem_ratio=$MEM_RATIO
rtlsim_configs=$RTLSIM_CONFIGS
vcd_file=$(basename "$VCD_FILE")
vcd_size_bytes=$VCD_SIZE
timestamp=$(date -Iseconds)
status=$STATUS
elapsed_sec=$ELAPSED
cycles=$CYCLES
instructions=$INSTRUCTIONS
EOF

echo "[$(date +%H:%M:%S)] Done: $CONFIG / $BENCHMARK ($STATUS, ${ELAPSED}s, VCD=$(( VCD_SIZE / 1024 / 1024 ))MB)"
