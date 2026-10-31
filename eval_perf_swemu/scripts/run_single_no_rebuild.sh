#!/bin/bash
# Run a single performance experiment (SW emulation approach)
# Usage: ./run_single.sh <config> <mem_ratio> <benchmark>
#
# This script reads config.mk files and uses modified benchmarks for soft math

CONFIG=$1
MEM_RATIO=$2
BENCHMARK=$3
OPTS_OVERRIDE="$4"  # Optional: override OPTS (benchmark arguments), use __ for spaces

if [ -z "$CONFIG" ] || [ -z "$MEM_RATIO" ] || [ -z "$BENCHMARK" ]; then
    echo "Usage: $0 <config> <mem_ratio> <benchmark> [opts_override]"
    echo "Example: $0 baseline 1.0 sgemm3"
    echo "Example: $0 baseline 1.0 sgemm3 '-n64'"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EVAL_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(dirname "$EVAL_DIR")"
VORTEX_DIR="$ROOT_DIR/vortex"
CONFIG_DIR="$EVAL_DIR/configs/$CONFIG"
RESULTS_TAG="${RESULTS_TAG:-}"
# RESULTS_ROOT lets a sweep redirect output to a separate tree (e.g. results_scaling)
# without touching the authoritative results_simx/. Defaults to results_simx (unchanged).
RESULTS_ROOT="${RESULTS_ROOT:-$EVAL_DIR/results_simx}"
if [ -n "$RESULTS_TAG" ]; then
    RESULTS_DIR="$RESULTS_ROOT/${CONFIG}_mem${MEM_RATIO}_${RESULTS_TAG}"
else
    RESULTS_DIR="$RESULTS_ROOT/${CONFIG}_mem${MEM_RATIO}"
fi
MODIFIED_BENCH_DIR="$EVAL_DIR/benchmarks_modified"

# Create results directory
mkdir -p "$RESULTS_DIR"

# Create unique temp directory to avoid race condition with /tmp/temp_kernel.bin
UNIQUE_TMPDIR="/tmp/vortex_$$_${CONFIG}_${BENCHMARK}"
mkdir -p "$UNIQUE_TMPDIR"
export TMPDIR="$UNIQUE_TMPDIR"

RESULT_FILE="$RESULTS_DIR/${BENCHMARK}.txt"
LOG_FILE="$RESULTS_DIR/${BENCHMARK}.log"

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
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue

        # Parse MARCH = value
        if [[ "$line" =~ ^[[:space:]]*MARCH[[:space:]]*=[[:space:]]*(.+)$ ]]; then
            MARCH="${BASH_REMATCH[1]}"
        fi

        # Parse MABI = value
        if [[ "$line" =~ ^[[:space:]]*MABI[[:space:]]*=[[:space:]]*(.+)$ ]]; then
            MABI="${BASH_REMATCH[1]}"
        fi

        # Parse CFLAGS += value
        if [[ "$line" =~ ^[[:space:]]*CFLAGS[[:space:]]*\+=[[:space:]]*(.+)$ ]]; then
            EXTRA_CFLAGS="$EXTRA_CFLAGS ${BASH_REMATCH[1]}"
        fi

        # Parse VX_CONFIG_OVERRIDE = value
        if [[ "$line" =~ ^[[:space:]]*VX_CONFIG_OVERRIDE[[:space:]]*=[[:space:]]*(.+)$ ]]; then
            VX_CONFIG_OVERRIDE="${BASH_REMATCH[1]}"
        fi

        # Parse USE_MODIFIED_BENCHMARKS = value
        if [[ "$line" =~ ^[[:space:]]*USE_MODIFIED_BENCHMARKS[[:space:]]*=[[:space:]]*(.+)$ ]]; then
            USE_MODIFIED_BENCHMARKS="${BASH_REMATCH[1]}"
        fi
    done < "$CONFIG_DIR/config.mk"
fi

# Determine benchmark directory
if [ "$USE_MODIFIED_BENCHMARKS" = "1" ]; then
    BENCH_DIR="$MODIFIED_BENCH_DIR/$BENCHMARK"
    if [ ! -d "$BENCH_DIR" ]; then
        echo "ERROR: Modified benchmark not found: $BENCH_DIR"
        echo "Run: $MODIFIED_BENCH_DIR/setup_benchmarks.sh"
        exit 1
    fi
else
    BENCH_DIR="$VORTEX_DIR/tests/opencl/$BENCHMARK"
fi

# Build CONFIG_ARGS from VX_CONFIG_OVERRIDE
CONFIG_ARGS=""
for def in $VX_CONFIG_OVERRIDE; do
    if [[ "$def" =~ ^-D(.+)$ ]]; then
        CONFIG_ARGS="$CONFIG_ARGS --define=${BASH_REMATCH[1]}"
    fi
done

# Add memory clock ratio
CONFIG_ARGS="$CONFIG_ARGS --define=MEM_CLOCK_RATIO=${MEM_RATIO}"

echo "[$(date +%H:%M:%S)] Running: $CONFIG / mem=$MEM_RATIO / $BENCHMARK"
echo "  MARCH=$MARCH MABI=$MABI"
echo "  USE_MODIFIED_BENCHMARKS=$USE_MODIFIED_BENCHMARKS"
echo "  EXTRA_CFLAGS=$EXTRA_CFLAGS"
echo "  POCL_EXTRA_BUILD_FLAGS=$EXTRA_CFLAGS"

# Record start
START_TIME=$(date +%s.%N)

# NOTE: simx rebuild skipped - assumed already built by run_parallel.sh

# Run simulation
{
    echo "=== Experiment Info ==="
    echo "Config: $CONFIG"
    echo "Memory Ratio: $MEM_RATIO"
    echo "Benchmark: $BENCHMARK"
    echo "Benchmark Dir: $BENCH_DIR"
    echo "MARCH: $MARCH"
    echo "MABI: $MABI"
    echo "EXTRA_CFLAGS: $EXTRA_CFLAGS"
    echo "POCL_EXTRA_BUILD_FLAGS: $EXTRA_CFLAGS"
    echo "VX_CONFIG_OVERRIDE: $VX_CONFIG_OVERRIDE"
    echo "USE_MODIFIED_BENCHMARKS: $USE_MODIFIED_BENCHMARKS"
    echo "Config Args: $CONFIG_ARGS"
    echo "Timestamp: $(date -Iseconds)"
    echo ""
    echo "=== Simulation Output ==="

    # Build and run from benchmark directory
    cd "$BENCH_DIR" 2>/dev/null || exit 1

    # Export environment
    export MARCH="$MARCH"
    export MABI="$MABI"
    export VORTEX_HOME="$VORTEX_DIR"
    # Default CORE perf class (1): ifetches, loads, stores, stalls. A caller may set
    # VORTEX_PROFILING=2 (MEM class) to additionally emit icache/dcache reads+misses;
    # the aggregate "PERF: instrs=, cycles=, IPC=" line is printed in BOTH classes, so
    # speedups stay comparable. Backward-compatible: defaults to 1 if unset.
    export VORTEX_PROFILING="${VORTEX_PROFILING:-1}"  # CORE counters; =2 adds cache miss rates
    export POCL_KERNEL_CACHE=0  # Disable PoCL kernel cache to ensure fresh compilation

    # Use correct TOOLDIR for PoCL (config.mk default may be wrong)
    TOOLDIR_ARG=""
    if [ -d "$ROOT_DIR/toolchain/pocl" ]; then
        TOOLDIR_ARG="TOOLDIR=$ROOT_DIR/toolchain"
    fi

    # Build (host code) with flock to prevent race conditions
    # Multiple (config, mem_ratio) groups share the same benchmark directory
    BUILD_STAMP_FILE=".simx_build_stamp"
    EXPECTED_BUILD="${CONFIG}_${MEM_RATIO}_${EXTRA_CFLAGS}"
    (
        flock -x 200
        CURRENT=$(cat "$BUILD_STAMP_FILE" 2>/dev/null)
        if [ "$CURRENT" != "$EXPECTED_BUILD" ] || [ ! -x "$BENCHMARK" ]; then
            make clean 2>/dev/null || true
            make MARCH="$MARCH" MABI="$MABI" $TOOLDIR_ARG 2>&1
            echo "$EXPECTED_BUILD" > "$BUILD_STAMP_FILE"
        fi
    ) 200>"$BENCH_DIR/.simx_build.lock"

    # Run simulation WITHOUT passing VX_CONFIG_OVERRIDE to avoid simx rebuild
    # simx is pre-built by run_parallel.sh with correct config
    # Only pass EXTRA_CFLAGS for kernel compilation (soft math defines)
    # Convert __ placeholders back to spaces in OPTS override
    if [ -n "$OPTS_OVERRIDE" ]; then
        OPTS_EXPANDED="${OPTS_OVERRIDE//__/ }"
    fi

    # CRITICAL: Pass soft-math defines to PoCL's OpenCL kernel compiler via
    # POCL_EXTRA_BUILD_FLAGS. CONFIGS only reaches the RISCV backend via
    # POCL_VORTEX_CFLAGS, but -D defines must reach the clang frontend
    # (OpenCL C -> LLVM IR) where #ifdef preprocessing happens.
    if [ -n "$EXTRA_CFLAGS" ]; then
        export POCL_EXTRA_BUILD_FLAGS="$EXTRA_CFLAGS"
    else
        unset POCL_EXTRA_BUILD_FLAGS 2>/dev/null || true
    fi

    if [ -n "$EXTRA_CFLAGS" ] && [ -n "$OPTS_OVERRIDE" ]; then
        make run-simx MARCH="$MARCH" MABI="$MABI" PERF=1 $TOOLDIR_ARG CONFIGS="$EXTRA_CFLAGS" OPTS="$OPTS_EXPANDED" 2>&1 || \
        echo "ERROR: Could not run benchmark."
    elif [ -n "$EXTRA_CFLAGS" ]; then
        make run-simx MARCH="$MARCH" MABI="$MABI" PERF=1 $TOOLDIR_ARG CONFIGS="$EXTRA_CFLAGS" 2>&1 || \
        echo "ERROR: Could not run benchmark."
    elif [ -n "$OPTS_OVERRIDE" ]; then
        make run-simx MARCH="$MARCH" MABI="$MABI" PERF=1 $TOOLDIR_ARG OPTS="$OPTS_EXPANDED" 2>&1 || \
        echo "ERROR: Could not run benchmark."
    else
        make run-simx MARCH="$MARCH" MABI="$MABI" PERF=1 $TOOLDIR_ARG 2>&1 || \
        echo "ERROR: Could not run benchmark."
    fi

} > "$LOG_FILE" 2>&1

END_TIME=$(date +%s.%N)
ELAPSED=$(echo "$END_TIME - $START_TIME" | bc 2>/dev/null || echo "0")

# Parse results from log
STATUS="COMPLETED"
CYCLES=""
INSTRUCTIONS=""
IPC=""

if grep -q "PASSED" "$LOG_FILE"; then
    STATUS="PASSED"
elif grep -q "FAILED" "$LOG_FILE"; then
    STATUS="FAILED"
elif grep -q "ERROR" "$LOG_FILE"; then
    STATUS="ERROR"
fi

# Try to extract performance metrics
CYCLES=$(grep -oP 'instrs=\d+, cycles=\K\d+' "$LOG_FILE" | tail -1)
INSTRUCTIONS=$(grep -oP 'instrs=\K\d+' "$LOG_FILE" | tail -1)
if [ -n "$CYCLES" ] && [ -n "$INSTRUCTIONS" ] && [ "$CYCLES" != "0" ]; then
    IPC=$(echo "scale=4; $INSTRUCTIONS / $CYCLES" | bc 2>/dev/null || echo "0")
fi

# Extract memory/cache stats from PERF output
IFETCHES=$(grep -oP 'PERF: ifetches=\K\d+' "$LOG_FILE" | tail -1)
LOADS=$(grep -oP 'PERF: loads=\K\d+' "$LOG_FILE" | tail -1)
STORES=$(grep -oP 'PERF: stores=\K\d+' "$LOG_FILE" | tail -1)
IFETCH_LAT=$(grep -oP 'PERF: ifetch latency=\K\d+' "$LOG_FILE" | tail -1)
LOAD_LAT=$(grep -oP 'PERF: load latency=\K\d+' "$LOG_FILE" | tail -1)

# Cache stats (icache)
ICACHE_READS=$(grep -oP 'icache reads=\K\d+' "$LOG_FILE" | tail -1)
ICACHE_MISSES=$(grep -oP 'icache read misses=\K\d+' "$LOG_FILE" | tail -1)
ICACHE_HIT_RATIO=$(grep -oP 'icache read misses=\d+ \(hit ratio=\K\d+' "$LOG_FILE" | tail -1)

# Cache stats (dcache)
DCACHE_READS=$(grep -oP 'dcache reads=\K\d+' "$LOG_FILE" | tail -1)
DCACHE_WRITES=$(grep -oP 'dcache writes=\K\d+' "$LOG_FILE" | tail -1)
DCACHE_READ_MISSES=$(grep -oP 'dcache read misses=\K\d+' "$LOG_FILE" | tail -1)
DCACHE_READ_HIT=$(grep -oP 'dcache read misses=\d+ \(hit ratio=\K\d+' "$LOG_FILE" | tail -1)
DCACHE_WRITE_MISSES=$(grep -oP 'dcache write misses=\K\d+' "$LOG_FILE" | tail -1)
DCACHE_WRITE_HIT=$(grep -oP 'dcache write misses=\d+ \(hit ratio=\K\d+' "$LOG_FILE" | tail -1)

# Stall stats
SCHED_IDLE=$(grep -oP 'scheduler idle=\K\d+' "$LOG_FILE" | tail -1)
SCHED_IDLE_PCT=$(grep -oP 'scheduler idle=\d+ \(\K\d+' "$LOG_FILE" | tail -1)
SCOREBOARD_STALLS=$(grep -oP 'scoreboard stalls=\K\d+' "$LOG_FILE" | tail -1)
SCOREBOARD_PCT=$(grep -oP 'scoreboard stalls=\d+ \(\K\d+' "$LOG_FILE" | tail -1)
LSU_PCT=$(grep -oP 'lsu=\K\d+' "$LOG_FILE" | tail -1)
ALU_PCT=$(grep -oP '\(alu=\K\d+' "$LOG_FILE" | tail -1)

# Write results
cat > "$RESULT_FILE" << EOF
config=$CONFIG
mem_ratio=$MEM_RATIO
benchmark=$BENCHMARK
use_modified=$USE_MODIFIED_BENCHMARKS
march=$MARCH
mabi=$MABI
extra_cflags=$EXTRA_CFLAGS
timestamp=$(date -Iseconds)
status=$STATUS
elapsed_sec=$ELAPSED
cycles=$CYCLES
instructions=$INSTRUCTIONS
ipc=$IPC
ifetches=$IFETCHES
loads=$LOADS
stores=$STORES
ifetch_latency=$IFETCH_LAT
load_latency=$LOAD_LAT
icache_reads=$ICACHE_READS
icache_misses=$ICACHE_MISSES
icache_hit_ratio=$ICACHE_HIT_RATIO
dcache_reads=$DCACHE_READS
dcache_writes=$DCACHE_WRITES
dcache_read_misses=$DCACHE_READ_MISSES
dcache_read_hit_ratio=$DCACHE_READ_HIT
dcache_write_misses=$DCACHE_WRITE_MISSES
dcache_write_hit_ratio=$DCACHE_WRITE_HIT
sched_idle=$SCHED_IDLE
sched_idle_pct=$SCHED_IDLE_PCT
scoreboard_stalls=$SCOREBOARD_STALLS
scoreboard_pct=$SCOREBOARD_PCT
lsu_pct=$LSU_PCT
alu_pct=$ALU_PCT
EOF

echo "[$(date +%H:%M:%S)] Done: $CONFIG / mem=$MEM_RATIO / $BENCHMARK ($STATUS, ${ELAPSED}s)"

# Cleanup unique temp directory
rm -rf "$UNIQUE_TMPDIR" 2>/dev/null
