#!/bin/bash
# Run a single performance experiment using RTL simulation (Verilator rtlsim)
# Usage: ./run_single_rtlsim.sh <config> <mem_ratio> <benchmark> [opts_override] [input_size_tag]
#
# This script:
#   1. Reads config.mk for VX_CONFIG_OVERRIDE and other flags
#   2. Builds libvortex-rtlsim.so + librtlsim.so with correct CONFIGS (only if stamp changed)
#   3. Runs the benchmark with VORTEX_DRIVER=rtlsim
#   4. Extracts perf counters and saves results
#
# NOTE: rtlsim rebuild is MUCH slower than simx (~10-30 min for Verilator compile).
#       The stamp mechanism avoids unnecessary rebuilds.
#       Within the same (config, mem_ratio) pair, no rebuild is needed.

CONFIG=$1
MEM_RATIO=$2
BENCHMARK=$3
OPTS_OVERRIDE="${4:-}"  # Optional: override OPTS (benchmark arguments), use __ for spaces
INPUT_SIZE_TAG="${5:-}"  # Optional: tag like "1x", "4x", "16x" for result filename

# Handle "_" placeholder for empty opts (used by jobs file)
if [ "$OPTS_OVERRIDE" = "_" ]; then
    OPTS_OVERRIDE=""
fi

# SKIP_RTLSIM_BUILD: set by run_parallel_rtlsim.sh when it has already pre-built
# This avoids redundant (and potentially racy) rebuilds when running in parallel
SKIP_RTLSIM_BUILD="${SKIP_RTLSIM_BUILD:-0}"

if [ -z "$CONFIG" ] || [ -z "$MEM_RATIO" ] || [ -z "$BENCHMARK" ]; then
    echo "Usage: $0 <config> <mem_ratio> <benchmark> [opts_override] [input_size_tag]"
    echo "Example: $0 baseline 1.0 sgemm3"
    echo "Example: $0 baseline 1.0 sgemm3 '-n64' 4x"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EVAL_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(dirname "$EVAL_DIR")"
VORTEX_DIR="$ROOT_DIR/vortex"
CONFIG_DIR="$EVAL_DIR/configs/$CONFIG"
MODIFIED_BENCH_DIR="$EVAL_DIR/benchmarks_modified"

# Results directory: results_rtlsim/<config>_mem<ratio>[_<tag>]/<benchmark>[_<input_size>].txt
RESULTS_TAG="${RESULTS_TAG:-}"
if [ -n "$RESULTS_TAG" ]; then
    RESULTS_DIR="$EVAL_DIR/results_rtlsim/${CONFIG}_mem${MEM_RATIO}_${RESULTS_TAG}"
elif [ -n "$INPUT_SIZE_TAG" ]; then
    RESULTS_DIR="$EVAL_DIR/results_rtlsim/${CONFIG}_mem${MEM_RATIO}"
else
    RESULTS_DIR="$EVAL_DIR/results_rtlsim/${CONFIG}_mem${MEM_RATIO}"
fi

mkdir -p "$RESULTS_DIR"

# Unique temp directory to avoid race conditions with kernel.bin
UNIQUE_TMPDIR=$(mktemp -d "/tmp/vortex_rtlsim_${CONFIG}_${BENCHMARK}_XXXXXX")  # fresh per run (no stale counter files)
export TMPDIR="$UNIQUE_TMPDIR"

# Result file naming: include input size tag if provided
if [ -n "$INPUT_SIZE_TAG" ]; then
    RESULT_FILE="$RESULTS_DIR/${BENCHMARK}_${INPUT_SIZE_TAG}.txt"
    LOG_FILE="$RESULTS_DIR/${BENCHMARK}_${INPUT_SIZE_TAG}.log"
else
    RESULT_FILE="$RESULTS_DIR/${BENCHMARK}.txt"
    LOG_FILE="$RESULTS_DIR/${BENCHMARK}.log"
fi

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
    if [ ! -d "$BENCH_DIR" ]; then
        echo "ERROR: Modified benchmark not found: $BENCH_DIR"
        exit 1
    fi
else
    BENCH_DIR="$VORTEX_DIR/tests/opencl/$BENCHMARK"
fi

# Build CONFIGS string for rtlsim rebuild
RTLSIM_CONFIGS="-DMEM_CLOCK_RATIO=${MEM_RATIO}"
if [ -n "$VX_CONFIG_OVERRIDE" ]; then
    RTLSIM_CONFIGS="$RTLSIM_CONFIGS $VX_CONFIG_OVERRIDE"
fi
# CAL energy rows: zero initial values and X assignments (sim/rtlsim/Makefile), so data-bus flip counts do not depend on the seed
[ "$RESULTS_TAG" = "energy" ] && RTLSIM_CONFIGS="$RTLSIM_CONFIGS -DVERILATOR_RESET_VALUE=0"

# Real-RTL guard (CAL): refuse energy runs whose build would not match the routed layouts
source "$(dirname "${BASH_SOURCE[0]}")/check_realrtl.sh"
REALRTL_VERIFIED=0
BUILD_ID=""; LIB_STAMP=""; LIB_START=""; LIB_END=""
realrtl_fail() {
    echo "ERROR: real-RTL check failed: $1"
    mkdir -p "$RESULTS_DIR"
    # never overwrite a finished row with a refusal (a manual rerun that is refused must not destroy an accepted result)
    local out="$RESULT_FILE"
    grep -qE '^status=(PASSED|COMPLETED)$' "$RESULT_FILE" 2>/dev/null && out="${RESULT_FILE%.txt}.refused.txt"
    printf "config=%s\nmem_ratio=%s\nbenchmark=%s\ninput_size=%s\nrtlsim_configs=%s\nstatus=CONFIG_MISMATCH\nerror=%s\ntimestamp=%s\n" \
        "$CONFIG" "$MEM_RATIO" "$BENCHMARK" "$INPUT_SIZE_TAG" "$RTLSIM_CONFIGS" "$1" "$(date -Iseconds)" > "$out"
    rm -rf "$UNIQUE_TMPDIR" 2>/dev/null
    exit 1
}
if realrtl_required; then
    why=$(check_realrtl_configs "$RTLSIM_CONFIGS") || realrtl_fail "$why"
    [ "$SKIP_RTLSIM_BUILD" = "1" ] || realrtl_fail "CAL runs must use the parallel runner's stamped build (SKIP_RTLSIM_BUILD=1)"
    [ -z "$(realrtl_env_dirty)" ] || realrtl_fail "environment variables would change the build or run: $(realrtl_env_dirty | tr '\n' ' ')"
    BUILD_ID=$(cat "$VORTEX_DIR/runtime/librtlsim.buildid" 2>/dev/null)
    [ -n "$BUILD_ID" ] || realrtl_fail "no build id stamp (runtime/librtlsim.buildid)"
    [ -z "${CAMPAIGN_BUILD_ID:-}" ] || [ "$BUILD_ID" = "$CAMPAIGN_BUILD_ID" ] || realrtl_fail "build id $BUILD_ID != campaign build id $CAMPAIGN_BUILD_ID"
    # the library on disk is the one the runner built and stamped, and the sources still match its id (committed, clean)
    LIB_STAMP=$(cat "$VORTEX_DIR/runtime/librtlsim.md5" 2>/dev/null)
    [[ "$LIB_STAMP" =~ ^librtlsim=[0-9a-f]{12}\ libvortex=[0-9a-f]{12}$ ]] || realrtl_fail "no library md5 stamp (runtime/librtlsim.md5)"
    LIB_START=$(sim_lib_md5s "$VORTEX_DIR")
    [ "$LIB_START" = "$LIB_STAMP" ] || realrtl_fail "runtime libraries ($LIB_START) != the runner's stamp ($LIB_STAMP)"
    live_id=$(sim_build_id "$VORTEX_DIR") || realrtl_fail "cannot compute the build id: $live_id"
    [ "$live_id" = "$BUILD_ID" ] || realrtl_fail "sources changed since the build (build id $live_id, library $BUILD_ID)"
    [ -z "$(sim_tree_dirty "$VORTEX_DIR")" ] || realrtl_fail "uncommitted simulation sources: $(sim_tree_dirty "$VORTEX_DIR" | tr '\n' ' ')"
fi

# Build CONFIG_ARGS for run invocation (--define= format, not used for rtlsim rebuild)
CONFIG_ARGS=""
for def in $VX_CONFIG_OVERRIDE; do
    if [[ "$def" =~ ^-D(.+)$ ]]; then
        CONFIG_ARGS="$CONFIG_ARGS --define=${BASH_REMATCH[1]}"
    fi
done
CONFIG_ARGS="$CONFIG_ARGS --define=MEM_CLOCK_RATIO=${MEM_RATIO}"

echo "[$(date +%H:%M:%S)] RTLsim: $CONFIG / mem=$MEM_RATIO / $BENCHMARK (input=${INPUT_SIZE_TAG:-default})"
echo "  MARCH=$MARCH MABI=$MABI"
echo "  RTLSIM_CONFIGS=$RTLSIM_CONFIGS"
echo "  USE_MODIFIED_BENCHMARKS=$USE_MODIFIED_BENCHMARKS"
echo "  EXTRA_CFLAGS=$EXTRA_CFLAGS"

START_TIME=$(date +%s.%N)

# ============================================================
# Step 1: Build rtlsim (librtlsim.so + libvortex-rtlsim.so)
# The stamp mechanism handles rebuild detection automatically.
# Make will compare CONFIGS in the stamp file and only rebuild
# if the flags changed.
#
# When called from run_parallel_rtlsim.sh, SKIP_RTLSIM_BUILD=1
# because the parallel runner pre-builds for the entire group.
# ============================================================

RTLSIM_BUILD_TIME="0"

if [ "$SKIP_RTLSIM_BUILD" = "1" ]; then
    echo "  Skipping rtlsim build (pre-built by parallel runner)"
    # CAL energy: the pre-built library must have been built with exactly this run's CONFIGS (stamp written by the runner)
    if realrtl_required && [ "$(echo $(cat "$VORTEX_DIR/runtime/librtlsim.configs" 2>/dev/null))" != "$(echo $RTLSIM_CONFIGS)" ]; then
        realrtl_fail "pre-built librtlsim.so stamp ($(cat "$VORTEX_DIR/runtime/librtlsim.configs" 2>/dev/null)) != run CONFIGS ($RTLSIM_CONFIGS)"
    fi
    # Verify the libraries exist
    if [ ! -f "$VORTEX_DIR/runtime/librtlsim.so" ] || [ ! -f "$VORTEX_DIR/runtime/libvortex-rtlsim.so" ]; then
        echo "ERROR: SKIP_RTLSIM_BUILD=1 but libraries not found!"
        cat > "$RESULT_FILE" << EOF
config=$CONFIG
mem_ratio=$MEM_RATIO
benchmark=$BENCHMARK
input_size=$INPUT_SIZE_TAG
status=BUILD_FAILED
error=Pre-built libraries not found
timestamp=$(date -Iseconds)
EOF
        rm -rf "$UNIQUE_TMPDIR" 2>/dev/null
        exit 1
    fi
else
    runtime_lock_or_die "$VORTEX_DIR"
    RTLSIM_BUILD_START=$(date +%s.%N)

    # Build librtlsim.so (Verilator-compiled RTL + processor.cpp)
    # This is the expensive step (~10-30 min on first build per config)
    echo "  Building librtlsim.so with CONFIGS='$RTLSIM_CONFIGS' ..."
    if ! make -C "$VORTEX_DIR/sim/rtlsim" \
        DESTDIR="$VORTEX_DIR/runtime" \
        VORTEX_HOME="$VORTEX_DIR" \
        CONFIGS="$RTLSIM_CONFIGS" \
        PERF=1 \
        "$VORTEX_DIR/runtime/librtlsim.so" 2>"$RESULTS_DIR/${BENCHMARK}_rtlsim_build.log"; then
        echo "ERROR: librtlsim.so build failed! See $RESULTS_DIR/${BENCHMARK}_rtlsim_build.log"
        cat > "$RESULT_FILE" << EOF
config=$CONFIG
mem_ratio=$MEM_RATIO
benchmark=$BENCHMARK
input_size=$INPUT_SIZE_TAG
status=BUILD_FAILED
error=librtlsim.so build failed
timestamp=$(date -Iseconds)
EOF
        rm -rf "$UNIQUE_TMPDIR" 2>/dev/null
        exit 1
    fi

    # Build libvortex-rtlsim.so (runtime wrapper)
    echo "  Building libvortex-rtlsim.so ..."
    if ! make -C "$VORTEX_DIR/runtime/rtlsim" \
        DESTDIR="$VORTEX_DIR/runtime" \
        VORTEX_HOME="$VORTEX_DIR" \
        CONFIGS="$RTLSIM_CONFIGS" \
        PERF=1 2>>"$RESULTS_DIR/${BENCHMARK}_rtlsim_build.log"; then
        echo "ERROR: libvortex-rtlsim.so build failed!"
        cat > "$RESULT_FILE" << EOF
config=$CONFIG
mem_ratio=$MEM_RATIO
benchmark=$BENCHMARK
input_size=$INPUT_SIZE_TAG
status=BUILD_FAILED
error=libvortex-rtlsim.so build failed
timestamp=$(date -Iseconds)
EOF
        rm -rf "$UNIQUE_TMPDIR" 2>/dev/null
        exit 1
    fi

    RTLSIM_BUILD_END=$(date +%s.%N)
    RTLSIM_BUILD_TIME=$(echo "$RTLSIM_BUILD_END - $RTLSIM_BUILD_START" | bc 2>/dev/null || echo "0")
    echo "  rtlsim build: ${RTLSIM_BUILD_TIME}s"
fi

if realrtl_required; then
    why=$(check_realrtl_lib "$VORTEX_DIR/runtime/librtlsim.so" "$RTLSIM_CONFIGS") || realrtl_fail "$why"
    REALRTL_VERIFIED=1
fi

# ============================================================
# Step 2: Run simulation
# ============================================================
{
    echo "=== RTLsim Experiment Info ==="
    echo "Config: $CONFIG"
    echo "Memory Ratio: $MEM_RATIO"
    echo "Benchmark: $BENCHMARK"
    echo "Input Size Tag: $INPUT_SIZE_TAG"
    echo "Benchmark Dir: $BENCH_DIR"
    echo "MARCH: $MARCH"
    echo "MABI: $MABI"
    echo "EXTRA_CFLAGS: $EXTRA_CFLAGS"
    echo "VX_CONFIG_OVERRIDE: $VX_CONFIG_OVERRIDE"
    echo "RTLSIM_CONFIGS: $RTLSIM_CONFIGS"
    echo "USE_MODIFIED_BENCHMARKS: $USE_MODIFIED_BENCHMARKS"
    echo "Config Args: $CONFIG_ARGS"
    echo "Timestamp: $(date -Iseconds)"
    echo ""
    echo "=== Simulation Output ==="

    cd "$BENCH_DIR" 2>/dev/null || exit 1

    export MARCH="$MARCH"
    export MABI="$MABI"
    export VORTEX_HOME="$VORTEX_DIR"
    if [ "${VX_CMDSTATS_ON:-0}" = "1" ]; then export VX_DRAM_CMDSTATS="$UNIQUE_TMPDIR/dramcmd"; else unset VX_DRAM_CMDSTATS VX_DRAM_SHADOW_MODE; fi   # CAL energy: opt-in per-run DRAM command counts (needs libramulator with VxCmdStats)
    # CAL energy: sim-only RTL activity counters (VX_sim_ctrs) to a private per-run file
    if [ "${VX_CTR_ON:-0}" = "1" ] || [ "${VX_CMDSTATS_ON:-0}" = "1" ]; then export VX_CTR_FILE="$UNIQUE_TMPDIR/vx.ctr"; else unset VX_CTR_FILE; fi
    export VORTEX_PROFILING=1
    export POCL_KERNEL_CACHE=0  # Disable PoCL kernel cache to ensure fresh compilation

    # CRITICAL: Pass soft-math defines to PoCL's OpenCL kernel compiler via
    # POCL_EXTRA_BUILD_FLAGS. CONFIGS only reaches the RISCV backend via
    # POCL_VORTEX_CFLAGS, but -D defines must reach the clang frontend
    # (OpenCL C -> LLVM IR) where #ifdef preprocessing happens.
    if [ -n "$EXTRA_CFLAGS" ]; then
        export POCL_EXTRA_BUILD_FLAGS="$EXTRA_CFLAGS"
    else
        unset POCL_EXTRA_BUILD_FLAGS 2>/dev/null || true
    fi

    TOOLDIR_ARG=""
    if [ -d "$ROOT_DIR/toolchain/pocl" ]; then
        TOOLDIR_ARG="TOOLDIR=$ROOT_DIR/toolchain"
    fi

    # Build host code (with flock to prevent races between parallel input sizes)
    # Only clean+rebuild if binary doesn't exist or config stamp changed
    BUILD_STAMP_FILE=".rtlsim_build_stamp"
    EXPECTED_STAMP="${CONFIG}_${MEM_RATIO}_${EXTRA_CFLAGS}_${BUILD_ID}"   # BUILD_ID: rebuild after any committed source change
    (
        flock -x 200
        CURRENT_STAMP=$(cat "$BUILD_STAMP_FILE" 2>/dev/null)
        if [ "$CURRENT_STAMP" != "$EXPECTED_STAMP" ] || [ ! -x "$BENCHMARK" ]; then
            make clean 2>/dev/null || true
            make MARCH="$MARCH" MABI="$MABI" $TOOLDIR_ARG 2>&1
            echo "$EXPECTED_STAMP" > "$BUILD_STAMP_FILE"
        fi
        # the host binary itself (the default target may not build it; run-rtlsim would, right before running it):
        # built here with the variables run-rtlsim passes, so it exists, and is hashed, before the run starts
        make MARCH="$MARCH" MABI="$MABI" $TOOLDIR_ARG ${EXTRA_CFLAGS:+CONFIGS="$EXTRA_CFLAGS"} "$BENCHMARK" 2>&1
    ) 200>"$BENCH_DIR/.rtlsim_build.lock"
    BENCH_MD5_START=$(md5sum < "$BENCH_DIR/$BENCHMARK" 2>/dev/null | cut -c1-12)
    # kernel runtime library the PoCL kernel link uses (benchmarks_modified/common.mk: -DUSE_SOFT_IDIV in CONFIGS -> kernel/softdiv)
    if [ "$USE_MODIFIED_BENCHMARKS" = "1" ] && [[ " $EXTRA_CFLAGS " == *" -DUSE_SOFT_IDIV "* ]]; then KERNEL_LIB=kernel/softdiv/libvortex.a; else KERNEL_LIB=kernel/libvortex.a; fi
    KERNEL_LIB_MD5=$(md5sum < "$VORTEX_DIR/$KERNEL_LIB" 2>/dev/null | cut -c1-12)

    # Convert __ placeholders back to spaces in OPTS override
    if [ -n "$OPTS_OVERRIDE" ]; then
        OPTS_EXPANDED="${OPTS_OVERRIDE//__/ }"
    fi

    # Optional per-run time limit (CAL campaign): VX_RUN_TIMEOUT seconds, 0/unset = none; kill 60 s after TERM
    RUN_TO=""
    if [ "${VX_RUN_TIMEOUT:-0}" != "0" ]; then RUN_TO="timeout -k 60 ${VX_RUN_TIMEOUT}"; fi
    # Run with VORTEX_DRIVER=rtlsim (uses run-rtlsim make target)
    if [ -n "$EXTRA_CFLAGS" ] && [ -n "$OPTS_OVERRIDE" ]; then
        $RUN_TO make run-rtlsim MARCH="$MARCH" MABI="$MABI" PERF=1 $TOOLDIR_ARG CONFIGS="$EXTRA_CFLAGS" OPTS="$OPTS_EXPANDED" 2>&1 || \
        { rc=$?; RUN_RC=$rc; { [ "$rc" = "124" ] || [ "$rc" = "137" ]; } && [ -n "$RUN_TO" ] && echo "RUN_TIMEOUT after ${VX_RUN_TIMEOUT}s (rc=$rc)"; echo "ERROR: Could not run benchmark."; }
    elif [ -n "$EXTRA_CFLAGS" ]; then
        $RUN_TO make run-rtlsim MARCH="$MARCH" MABI="$MABI" PERF=1 $TOOLDIR_ARG CONFIGS="$EXTRA_CFLAGS" 2>&1 || \
        { rc=$?; RUN_RC=$rc; { [ "$rc" = "124" ] || [ "$rc" = "137" ]; } && [ -n "$RUN_TO" ] && echo "RUN_TIMEOUT after ${VX_RUN_TIMEOUT}s (rc=$rc)"; echo "ERROR: Could not run benchmark."; }
    elif [ -n "$OPTS_OVERRIDE" ]; then
        $RUN_TO make run-rtlsim MARCH="$MARCH" MABI="$MABI" PERF=1 $TOOLDIR_ARG OPTS="$OPTS_EXPANDED" 2>&1 || \
        { rc=$?; RUN_RC=$rc; { [ "$rc" = "124" ] || [ "$rc" = "137" ]; } && [ -n "$RUN_TO" ] && echo "RUN_TIMEOUT after ${VX_RUN_TIMEOUT}s (rc=$rc)"; echo "ERROR: Could not run benchmark."; }
    else
        $RUN_TO make run-rtlsim MARCH="$MARCH" MABI="$MABI" PERF=1 $TOOLDIR_ARG 2>&1 || \
        { rc=$?; RUN_RC=$rc; { [ "$rc" = "124" ] || [ "$rc" = "137" ]; } && [ -n "$RUN_TO" ] && echo "RUN_TIMEOUT after ${VX_RUN_TIMEOUT}s (rc=$rc)"; echo "ERROR: Could not run benchmark."; }
    fi

} > "$LOG_FILE" 2>&1

END_TIME=$(date +%s.%N)
ELAPSED=$(echo "$END_TIME - $START_TIME" | bc 2>/dev/null || echo "0")

# ============================================================
# Step 3: Parse results from log
# ============================================================
STATUS="COMPLETED"
CYCLES=""
INSTRUCTIONS=""
IPC=""

if grep -q "^RUN_TIMEOUT" "$LOG_FILE"; then
    STATUS="TIMEOUT"
elif grep -q "PASSED" "$LOG_FILE"; then
    STATUS="PASSED"
elif grep -q "FAILED" "$LOG_FILE"; then
    STATUS="FAILED"
elif grep -q "ERROR" "$LOG_FILE"; then
    STATUS="ERROR"
fi

# CAL energy: the counter file must be complete (END marker after the final dump); keep a gzipped copy next to the result
CTR_FILE_OUT=""
CTR_STATUS=""
CTR_ERROR=""
if [ "${VX_CTR_ON:-0}" = "1" ] || [ "${VX_CMDSTATS_ON:-0}" = "1" ]; then
    CTR_STATUS="OK"
    if [ -s "$UNIQUE_TMPDIR/vx.ctr" ] && [ "$(tail -n 1 "$UNIQUE_TMPDIR/vx.ctr")" = "END" ] \
       && [ "$(grep -c '^H vx_ctr' "$UNIQUE_TMPDIR/vx.ctr")" = "1" ]; then
        CTR_FILE_OUT="$RESULTS_DIR/${BENCHMARK}${INPUT_SIZE_TAG:+_$INPUT_SIZE_TAG}.ctr.gz"
        gzip -c "$UNIQUE_TMPDIR/vx.ctr" > "$CTR_FILE_OUT"
    else
        echo "ERROR: counter file missing or incomplete"
        CTR_STATUS="CTR_MISSING"; CTR_ERROR="${CTR_ERROR}ctr_file_missing_or_incomplete "
    fi
fi

# Extract performance metrics (same format as simx perf output)
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
SCHED_IDLE=$(grep -oP 'PERF: scheduler idle=\K\d+' "$LOG_FILE" | tail -1)
SCHED_IDLE_PCT=$(grep -oP 'PERF: scheduler idle=\d+ \(\K\d+' "$LOG_FILE" | tail -1)
SCHED_STALLS=$(grep -oP 'PERF: scheduler stalls=\K\d+' "$LOG_FILE" | tail -1)
SCHED_STALLS_PCT=$(grep -oP 'PERF: scheduler stalls=\d+ \(\K\d+' "$LOG_FILE" | tail -1)
IBUFFER_STALLS=$(grep -oP 'PERF: ibuffer stalls=\K\d+' "$LOG_FILE" | tail -1)
IBUFFER_PCT=$(grep -oP 'PERF: ibuffer stalls=\d+ \(\K\d+' "$LOG_FILE" | tail -1)
SCOREBOARD_STALLS=$(grep -oP 'PERF: scoreboard stalls=\K\d+' "$LOG_FILE" | tail -1)
SCOREBOARD_PCT=$(grep -oP 'PERF: scoreboard stalls=\d+ \(\K\d+' "$LOG_FILE" | tail -1)
LSU_PCT=$(grep -oP 'lsu=\K\d+' "$LOG_FILE" | tail -1)
ALU_PCT=$(grep -oP '\(alu=\K\d+' "$LOG_FILE" | tail -1)
FPU_PCT=$(grep -oP 'fpu=\K\d+' "$LOG_FILE" | tail -1)
OPDS_STALLS=$(grep -oP 'PERF: operands stalls=\K\d+' "$LOG_FILE" | tail -1)
OPDS_PCT=$(grep -oP 'PERF: operands stalls=\d+ \(\K\d+' "$LOG_FILE" | tail -1)

# Memory-class perf counters (if VORTEX_PROFILING=2 was used)
MEM_READS=$(grep -oP 'PERF: memory requests=\d+ \(reads=\K\d+' "$LOG_FILE" | tail -1)
MEM_WRITES=$(grep -oP 'writes=\K\d+' "$LOG_FILE" | tail -1)
MEM_LAT=$(grep -oP 'PERF: memory latency=\K\d+' "$LOG_FILE" | tail -1)

# Ramulator stats: check for ramulator log files in benchmark dir
RAMULATOR_STATS=""
if [ "${VX_CMDSTATS_ON:-0}" != "1" ] && [ -d "$BENCH_DIR/trace" ]; then
    for rlog in "$BENCH_DIR"/trace/ramulator.log.ch*; do
        if [ -f "$rlog" ]; then
            LINES=$(wc -l < "$rlog")
            RAMULATOR_STATS="${RAMULATOR_STATS}$(basename "$rlog"):${LINES}lines "
        fi
    done
fi

# CAL energy DRAM statistics (VX_CMDSTATS_ON): timing and shadow command counts per channel, the DramSim summary.
# Every file must be present and complete, else the run is CTR_MISSING. Channel files are summed into the result
# (dram_timing_* / dram_shadow_*), the summary is copied (dram_sum_*), and all raw files are archived next to the result.
DRAM_CMD_FIELDS=""
DRAM_FILE_OUT=""
if [ "${VX_CMDSTATS_ON:-0}" = "1" ]; then
    dram_ok=1
    for inst in timing shadow; do
        n=$(ls "$UNIQUE_TMPDIR"/dramcmd.$inst.ch* 2>/dev/null | wc -l)
        [ "$n" = "2" ] || { echo "ERROR: expected 2 $inst channel files, found $n"; CTR_ERROR="${CTR_ERROR}${inst}_channel_files=$n "; dram_ok=0; }
        for fch in "$UNIQUE_TMPDIR"/dramcmd.$inst.ch*; do
            for key in ACT PRE PREA RD WR RDA WRA REFab REFsb PREA_banks_closed ACT_reopen_PREA REF_to_ACT_min ticks open_ticks ticks_run open_ticks_run; do
                grep -q "^$key=" "$fch" 2>/dev/null || { echo "ERROR: $key missing in $fch"; CTR_ERROR="${CTR_ERROR}missing_${key}_$(basename "$fch") "; dram_ok=0; }
            done
        done
    done
    if ! grep -qx "END" "$UNIQUE_TMPDIR/dramcmd.summary" 2>/dev/null || ! grep -qx "drained=1" "$UNIQUE_TMPDIR/dramcmd.summary" \
       || ! grep -qx "shadow_mode=physical" "$UNIQUE_TMPDIR/dramcmd.summary"; then
        echo "ERROR: DRAM summary missing, incomplete or not drained"; CTR_ERROR="${CTR_ERROR}dram_summary "; dram_ok=0
    fi
    if [ "$dram_ok" = "1" ]; then
        for inst in timing shadow; do
            DRAM_CMD_FIELDS="$DRAM_CMD_FIELDS$(cat "$UNIQUE_TMPDIR"/dramcmd.$inst.ch* | awk -F= -v P="dram_${inst}_" '$1!="REF_to_ACT_min" && $1!~/ticks/ {s[$1]+=$2; if(!($1 in o)){o[$1]=++n; k[n]=$1}} $1~/ticks/ {ts[$1]+=$2; if($2>tm[$1])tm[$1]=$2; if(!($1 in to)){to[$1]=++q; tk[q]=$1}} $1=="REF_to_ACT_min" && $2!="NA" {if(m==""||$2+0<m)m=$2+0} END{for(i=1;i<=n;i++) printf "%s%s=%d\n", P, k[i], s[k[i]]; for(i=1;i<=q;i++) printf "%s%s_sum=%d\n%s%s_max=%d\n", P, tk[i], ts[tk[i]], P, tk[i], tm[tk[i]]; printf "%sREF_to_ACT_min=%s\n", P, (m==""?"NA":m)}')
"
        done
        DRAM_CMD_FIELDS="$DRAM_CMD_FIELDS$(grep -v '^END$' "$UNIQUE_TMPDIR/dramcmd.summary" | sed 's/^/dram_sum_/')"
        # shadow lag: end-of-run drain relative to the run, and mean backlog (flagged, not rejected; see ENERGY_PLAN)
        DRAM_CMD_FIELDS="$DRAM_CMD_FIELDS
$(awk -F= '$1=="drain_ticks"{d=$2} $1=="dram_ticks_run"{t=$2} $1=="shadow_backlog_sum"{b=$2} END{printf "dram_shadow_lag_frac=%.6f\ndram_shadow_backlog_mean=%.3f\n", (t>0?d/t:0), (t>0?b/t:0)}' "$UNIQUE_TMPDIR/dramcmd.summary")"
        DRAM_FILE_OUT="$RESULTS_DIR/${BENCHMARK}${INPUT_SIZE_TAG:+_$INPUT_SIZE_TAG}.dram.tgz"
        tar -czf "$DRAM_FILE_OUT" -C "$UNIQUE_TMPDIR" $(cd "$UNIQUE_TMPDIR" && ls dramcmd.*)
    else
        CTR_STATUS="CTR_MISSING"
    fi
fi
# CAL energy: the same checks at the end of the run (library not swapped, sources unchanged and clean while it ran)
RUN_END_CHECK=""
if realrtl_required; then
    LIB_END=$(sim_lib_md5s "$VORTEX_DIR")
    end_id=$(sim_build_id "$VORTEX_DIR" 2>&1)
    [ "$LIB_END" = "$LIB_STAMP" ] || RUN_END_CHECK="libraries changed during the run ($LIB_END);"
    [ "$end_id" = "$BUILD_ID" ] || RUN_END_CHECK="$RUN_END_CHECK sources changed during the run ($end_id);"
    [ -z "$(sim_tree_dirty "$VORTEX_DIR")" ] || RUN_END_CHECK="$RUN_END_CHECK uncommitted sources at the end of the run;"
    RUN_END_CHECK="${RUN_END_CHECK:-OK}"
fi
# provenance of this run's simulator (CAL energy): library md5s and the repository commit (+dirty flag)
PROVENANCE="librtlsim=$(md5sum < "$VORTEX_DIR/runtime/librtlsim.so" 2>/dev/null | cut -c1-12) libramulator=$(md5sum < "$VORTEX_DIR/third_party/ramulator/libramulator.so" 2>/dev/null | cut -c1-12) git=$(git -C "$VORTEX_DIR" rev-parse --short HEAD 2>/dev/null)$([ "$(cat "$VORTEX_DIR/runtime/librtlsim.tree" 2>/dev/null)" = "clean" ] || echo +dirty) ramulator_git=$(git -C "$VORTEX_DIR/third_party/ramulator" rev-parse --short HEAD 2>/dev/null) build_configs=$(cat "$VORTEX_DIR/runtime/librtlsim.configs" 2>/dev/null | tr ' ' ',')"

# Write results
cat > "$RESULT_FILE.tmp" << EOF
config=$CONFIG
mem_ratio=$MEM_RATIO
benchmark=$BENCHMARK
input_size=$INPUT_SIZE_TAG
simulator=rtlsim
use_modified=$USE_MODIFIED_BENCHMARKS
march=$MARCH
mabi=$MABI
extra_cflags=$EXTRA_CFLAGS
rtlsim_configs=$RTLSIM_CONFIGS
realrtl_verified=$REALRTL_VERIFIED
build_id=$BUILD_ID
runner=$(basename "$0")
bench_md5=$BENCH_MD5_START
bench_md5_end=$(md5sum < "$BENCH_DIR/$BENCHMARK" 2>/dev/null | cut -c1-12)
kernel_lib=${KERNEL_LIB:-}
kernel_lib_md5=${KERNEL_LIB_MD5:-}
run_rc=${RUN_RC:-0}
lib_md5_stamp=$LIB_STAMP
lib_md5_start=$LIB_START
lib_md5_end=$LIB_END
run_end_check=$RUN_END_CHECK
opts=$OPTS_OVERRIDE
ctr_file=$CTR_FILE_OUT
ctr_status=$CTR_STATUS
self_check=passed:$(grep -cE '^(Passed!|PASSED!?)$' "$LOG_FILE" 2>/dev/null) failed:$(grep -cE '^(Failed!|FAILED!?)( |$)' "$LOG_FILE" 2>/dev/null)
ctr_error=$CTR_ERROR
provenance=$PROVENANCE
dram_file=$DRAM_FILE_OUT
timestamp=$(date -Iseconds)
status=$STATUS
elapsed_sec=$ELAPSED
rtlsim_build_sec=$RTLSIM_BUILD_TIME
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
sched_stalls=$SCHED_STALLS
sched_stalls_pct=$SCHED_STALLS_PCT
ibuffer_stalls=$IBUFFER_STALLS
ibuffer_pct=$IBUFFER_PCT
scoreboard_stalls=$SCOREBOARD_STALLS
scoreboard_pct=$SCOREBOARD_PCT
lsu_pct=$LSU_PCT
alu_pct=$ALU_PCT
fpu_pct=$FPU_PCT
opds_stalls=$OPDS_STALLS
opds_pct=$OPDS_PCT
mem_reads=$MEM_READS
mem_writes=$MEM_WRITES
mem_latency=$MEM_LAT
ramulator_stats=$RAMULATOR_STATS
EOF
[ -n "$DRAM_CMD_FIELDS" ] && echo "$DRAM_CMD_FIELDS" >> "$RESULT_FILE.tmp"
mv -f "$RESULT_FILE.tmp" "$RESULT_FILE"   # atomic: a killed run never leaves a half-written row

echo "[$(date +%H:%M:%S)] Done: $CONFIG / mem=$MEM_RATIO / $BENCHMARK ($STATUS, ${ELAPSED}s, build=${RTLSIM_BUILD_TIME}s)"

# Cleanup unique temp directory
rm -rf "$UNIQUE_TMPDIR" 2>/dev/null
