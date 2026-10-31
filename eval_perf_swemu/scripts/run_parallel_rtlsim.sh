#!/bin/bash
# Run all RTLsim experiments in parallel (grouped by CONFIG+MEM_RATIO to avoid rebuild conflicts)
# Usage: ./run_parallel_rtlsim.sh [num_parallel_jobs] [jobs_file]
# Example: ./run_parallel_rtlsim.sh 4 ../jobs_rtlsim.txt
#
# IMPORTANT: rtlsim must be rebuilt for each (config, mem_ratio) pair because:
#   - VX_CONFIG_OVERRIDE defines (L1_DISABLE, NUM_WARPS, etc.) are compile-time Verilator flags
#   - MEM_CLOCK_RATIO is a compile-time define in processor.cpp
#   - Both librtlsim.so and libvortex-rtlsim.so link against these
#
# Within each (config, mem_ratio) group, benchmarks can run in parallel since
# they all use the same pre-built shared libraries.
#
# Rebuild cost: ~10-30 min for Verilator compile (first time or when CONFIGS change)
#               Subsequent runs with same CONFIGS use stamp-based caching.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EVAL_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(dirname "$EVAL_DIR")"
VORTEX_DIR="$ROOT_DIR/vortex"
CONFIG_DIR="$EVAL_DIR/configs"

# Default parallelism: use fewer jobs than nproc since rtlsim is heavier than simx
NUM_JOBS=${1:-$(( $(nproc) / 2 > 0 ? $(nproc) / 2 : 1 ))}
JOBS_FILE="${2:-$EVAL_DIR/jobs_rtlsim.txt}"

export RESULTS_TAG="${RESULTS_TAG:-}"

# ============================================================
# Prerequisites
# ============================================================

# Check kernel library
if [ ! -f "$VORTEX_DIR/kernel/libvortex.a" ]; then
    echo "ERROR: libvortex.a not found. Building..."
    make -C "$VORTEX_DIR/kernel" || { echo "FATAL: Failed to build kernel library"; exit 1; }
fi

# Check stub library
if [ ! -f "$VORTEX_DIR/runtime/libvortex.so" ]; then
    echo "ERROR: libvortex.so (stub) not found. Building..."
    make -C "$VORTEX_DIR/runtime/stub" || { echo "FATAL: Failed to build stub library"; exit 1; }
fi

# Generate jobs if missing
if [ ! -f "$JOBS_FILE" ]; then
    echo "Jobs file not found. Generating..."
    "$SCRIPT_DIR/generate_jobs_rtlsim.sh"
fi

TOTAL=$(grep -v '^[[:space:]]*#' "$JOBS_FILE" | grep -v '^$' | wc -l)
echo "============================================"
echo "RTLsim Experiment Runner"
echo "============================================"
echo "Total experiments: $TOTAL"
echo "Parallel jobs per group: $NUM_JOBS"
echo "Jobs file: $JOBS_FILE"
echo "Results dir: $EVAL_DIR/results_rtlsim/"
echo ""

# Create results directory
mkdir -p "$EVAL_DIR/results_rtlsim"

# ============================================================
# Group jobs by (config, mem_ratio) for sequential rebuild
# ============================================================

# Get unique (config, ratio) pairs from jobs file (skip comments and blank lines)
PAIRS=($(awk '!/^[[:space:]]*#/ && NF>0 {print $1 ":" $2}' "$JOBS_FILE" | sort -u))

echo "Found ${#PAIRS[@]} unique (config, mem_ratio) groups"
echo "Each group requires one Verilator build, then benchmarks run in parallel"
echo ""

TOTAL_STARTED=0
TOTAL_GROUPS=${#PAIRS[@]}
GROUP_NUM=0

# Track timing
OVERALL_START=$(date +%s)

# one runner per tree: every group rebuilds the shared runtime/librtlsim.so
exec 9>"$VORTEX_DIR/runtime/.rtlsim_campaign.lock"
flock -n 9 || { echo "ERROR: another run_parallel campaign holds $VORTEX_DIR/runtime/.rtlsim_campaign.lock"; exit 1; }

SKIPPED_GROUPS=0   # Oct 27 (audit 18): groups whose library build failed; any skip makes the script exit non-zero
for pair in "${PAIRS[@]}"; do
    config="${pair%%:*}"
    ratio="${pair##*:}"
    GROUP_NUM=$((GROUP_NUM + 1))

    echo "========================================"
    echo "=== [$GROUP_NUM/$TOTAL_GROUPS] CONFIG=$config, MEM_RATIO=$ratio ==="
    echo "========================================"

    # Read VX_CONFIG_OVERRIDE from config.mk
    VX_CONFIG_OVERRIDE=""
    if [ -f "$CONFIG_DIR/$config/config.mk" ]; then
        # last uncommented VX_CONFIG_OVERRIDE line, as run_single_rtlsim.sh parses it
        VX_CONFIG_OVERRIDE=$(awk '/^[[:space:]]*VX_CONFIG_OVERRIDE[[:space:]]*=/{sub(/^[^=]*=[[:space:]]*/,""); v=$0} END{print v}' "$CONFIG_DIR/$config/config.mk")
    fi

    # Build CONFIGS string
    RTLSIM_CONFIGS="-DMEM_CLOCK_RATIO=${ratio}"
    if [ -n "$VX_CONFIG_OVERRIDE" ]; then
        RTLSIM_CONFIGS="$RTLSIM_CONFIGS $VX_CONFIG_OVERRIDE"
    fi
    # CAL energy rows: zero initial values and X assignments (sim/rtlsim/Makefile), so data-bus flip counts do not depend on the seed
    [ "$RESULTS_TAG" = "energy" ] && RTLSIM_CONFIGS="$RTLSIM_CONFIGS -DVERILATOR_RESET_VALUE=0"

    # Real-RTL guard (CAL): skip a group whose build would not match the routed layouts (each run would also refuse)
    source "$SCRIPT_DIR/check_realrtl.sh"
    if realrtl_required && ! why=$(check_realrtl_configs "$RTLSIM_CONFIGS"); then
        echo "ERROR: real-RTL check failed for $config (ratio $ratio): $why -- skipping this group"
        SKIPPED_GROUPS=$((SKIPPED_GROUPS + 1))
        continue
    fi
    # CAL energy: no inherited variable may change what is built or loaded (run_energy_wave.sh unsets them)
    if realrtl_required && [ -n "$(realrtl_env_dirty)" ]; then
        echo "ERROR: environment variables would change the build or run: $(realrtl_env_dirty | tr '\n' ' ')-- STOPPING"; exit 1
    fi
    # CAL energy: never build from uncommitted simulation sources (rows carry the build id of the committed tree)
    if realrtl_required && [ -n "$(sim_tree_dirty "$VORTEX_DIR")" ]; then
        echo "ERROR: uncommitted simulation sources ($(sim_tree_dirty "$VORTEX_DIR" | tr '\n' ' ')) -- STOPPING the campaign at $config/$ratio"
        exit 1
    fi
    if realrtl_required; then
        BUILD_ID_BEFORE=$(sim_build_id "$VORTEX_DIR") || { echo "ERROR: cannot compute the build id ($BUILD_ID_BEFORE) -- STOPPING"; exit 1; }
        # the campaign's id is frozen at launch: a source change mid-campaign stops it instead of silently starting a new id
        if [ -n "${CAMPAIGN_BUILD_ID:-}" ] && [ "$BUILD_ID_BEFORE" != "$CAMPAIGN_BUILD_ID" ]; then
            echo "ERROR: build id $BUILD_ID_BEFORE != campaign build id $CAMPAIGN_BUILD_ID (sources changed since launch) -- STOPPING"; exit 1
        fi
    fi

    # ============================================================
    # Pre-build rtlsim for this (config, ratio) pair
    # This is done ONCE, then all benchmarks in this group share it
    # ============================================================
    echo "Pre-building rtlsim with CONFIGS: $RTLSIM_CONFIGS"
    BUILD_START=$(date +%s)

    BUILD_LOG="$EVAL_DIR/results_rtlsim/build_${config}_mem${ratio}${RESULTS_TAG:+_$RESULTS_TAG}.log"

    # Clean build per group: verilator --build reuses C++ objects whose source did not change, so -D flags
    # read only by plain C++ files (MEM_LAT_SCALE/MEM_BW_SCALE in sim/common/dram_sim.cpp) were silently dropped.
    rm -rf "$VORTEX_DIR/runtime/librtlsim.so.obj_dir" "$VORTEX_DIR/runtime/librtlsim.so" "$VORTEX_DIR/runtime/libvortex-rtlsim.so" "$VORTEX_DIR/runtime/librtlsim.configs" "$VORTEX_DIR/runtime/librtlsim.buildid" "$VORTEX_DIR/runtime/librtlsim.tree" "$VORTEX_DIR/runtime/librtlsim.md5"

    # Build librtlsim.so (Verilator RTL compile - the expensive step). One clean retry: a 16t build once hit a
    # non-reproducible "Verilator internal fault" (Oct 27); the first attempt's log is kept as $BUILD_LOG.attempt1.
    build_ok=0
    for attempt in 1 2; do
        if make -C "$VORTEX_DIR/sim/rtlsim" \
            DESTDIR="$VORTEX_DIR/runtime" \
            VORTEX_HOME="$VORTEX_DIR" \
            CONFIGS="$RTLSIM_CONFIGS" \
            PERF=1 \
            "$VORTEX_DIR/runtime/librtlsim.so" > "$BUILD_LOG" 2>&1; then build_ok=1; break; fi
        if [ "$attempt" = 1 ]; then
            mv -f "$BUILD_LOG" "$BUILD_LOG.attempt1"
            echo "WARNING: librtlsim.so build failed for $config/$ratio (see $BUILD_LOG.attempt1); retrying once from clean"
            rm -rf "$VORTEX_DIR/runtime/librtlsim.so.obj_dir" "$VORTEX_DIR/runtime/librtlsim.so"
        fi
    done
    if [ "$build_ok" != 1 ]; then
        echo "ERROR: librtlsim.so build FAILED twice for $config/$ratio! Skipping group..."
        echo "  See: $BUILD_LOG.attempt1 and $BUILD_LOG"
        SKIPPED_GROUPS=$((SKIPPED_GROUPS + 1))
        continue
    fi

    # Build libvortex-rtlsim.so (runtime wrapper - fast)
    if ! make -C "$VORTEX_DIR/runtime/rtlsim" \
        DESTDIR="$VORTEX_DIR/runtime" \
        VORTEX_HOME="$VORTEX_DIR" \
        CONFIGS="$RTLSIM_CONFIGS" \
        PERF=1 >> "$BUILD_LOG" 2>&1; then
        echo "ERROR: libvortex-rtlsim.so build FAILED for $config/$ratio! Skipping group..."
        echo "  See: $BUILD_LOG"
        SKIPPED_GROUPS=$((SKIPPED_GROUPS + 1))
        continue
    fi

    # build stamp: the exact CONFIGS this group's library was built with (run_single checks it in CAL energy mode)
    printf "%s" "$RTLSIM_CONFIGS" > "$VORTEX_DIR/runtime/librtlsim.configs"
    if realrtl_required; then
        # the sources must not have changed during the build (else the library would be labelled with the wrong id)
        BUILD_ID_AFTER=$(sim_build_id "$VORTEX_DIR") || { echo "ERROR: cannot compute the build id -- STOPPING"; exit 1; }
        if [ "$BUILD_ID_AFTER" != "$BUILD_ID_BEFORE" ] || [ -n "$(sim_tree_dirty "$VORTEX_DIR")" ]; then
            echo "ERROR: simulation sources changed during the build of $config/$ratio -- STOPPING the campaign"; exit 1
        fi
        echo "$BUILD_ID_BEFORE" > "$VORTEX_DIR/runtime/librtlsim.buildid"
        echo "clean" > "$VORTEX_DIR/runtime/librtlsim.tree"
        # md5 of the libraries this group's runs must load (run_single checks it before and after each run)
        sim_lib_md5s "$VORTEX_DIR" > "$VORTEX_DIR/runtime/librtlsim.md5"
    else
        sim_build_id "$VORTEX_DIR" > "$VORTEX_DIR/runtime/librtlsim.buildid" 2>/dev/null
        if [ -z "$(sim_tree_dirty "$VORTEX_DIR")" ]; then echo clean; else echo dirty; fi > "$VORTEX_DIR/runtime/librtlsim.tree"
    fi

    BUILD_END=$(date +%s)
    BUILD_TIME=$((BUILD_END - BUILD_START))
    echo "  Build completed in ${BUILD_TIME}s"

    # ============================================================
    # Run all benchmarks for this (config, ratio) pair in parallel
    # Since rtlsim is already built, run_single_rtlsim.sh will
    # detect matching stamps and skip the rebuild step.
    #
    # IMPORTANT: Run input sizes in WAVES (all 1x, then 4x, then 16x)
    # to avoid race conditions. Multiple input sizes of the same benchmark
    # share a directory, so running them simultaneously causes "Text file busy"
    # and missing .o file errors from concurrent make clean/build/run.
    # ============================================================

    # Get jobs for this (config, ratio) pair
    PAIR_JOBS=$(awk -v c="$config" -v r="$ratio" '!/^[[:space:]]*#/ && $1==c && $2==r' "$JOBS_FILE")
    PAIR_COUNT=$(echo "$PAIR_JOBS" | wc -l)
    TOTAL_STARTED=$((TOTAL_STARTED + PAIR_COUNT))
    echo "  Running $PAIR_COUNT benchmarks in 3 waves (1x, 4x, 16x), max $NUM_JOBS concurrent per wave..."
    echo "  Progress: $TOTAL_STARTED / $TOTAL total"

    # Skip build in individual runs since we already pre-built above
    export SKIP_RTLSIM_BUILD=1

    # Run in waves by input size to prevent directory conflicts
    # Using bash background jobs + wait for reliable process management
    for wave_size in 1x 4x 16x; do
        WAVE_JOBS=$(echo "$PAIR_JOBS" | awk -v s="$wave_size" '$5==s')
        WAVE_COUNT=$(echo "$WAVE_JOBS" | grep -c '.' || true)
        if [ "$WAVE_COUNT" -eq 0 ]; then
            continue
        fi
        echo "    Wave $wave_size: $WAVE_COUNT benchmarks..."

        # Launch jobs with controlled parallelism using background processes
        RUNNING_PIDS=()
        while IFS=' ' read -r cfg ratio bench opts size; do
            [ -z "$cfg" ] && continue
            # Wait if at max parallelism
            while [ ${#RUNNING_PIDS[@]} -ge $NUM_JOBS ]; do
                # Wait for any one process to finish
                for i in "${!RUNNING_PIDS[@]}"; do
                    if ! kill -0 "${RUNNING_PIDS[$i]}" 2>/dev/null; then
                        unset 'RUNNING_PIDS[$i]'
                    fi
                done
                RUNNING_PIDS=("${RUNNING_PIDS[@]}")
                [ ${#RUNNING_PIDS[@]} -ge $NUM_JOBS ] && sleep 1
            done
            # Launch job in background
            SKIP_RTLSIM_BUILD=1 "$SCRIPT_DIR/run_single_rtlsim.sh" "$cfg" "$ratio" "$bench" "$opts" "$size" &
            RUNNING_PIDS+=($!)
        done <<< "$WAVE_JOBS"
        # Wait for ALL remaining jobs in this wave to complete
        for pid in "${RUNNING_PIDS[@]}"; do
            wait "$pid" 2>/dev/null || true   # one failed run must not abort the campaign (set -e)
        done
        echo "    Wave $wave_size: complete."
    done

    echo ""
done

OVERALL_END=$(date +%s)
OVERALL_TIME=$((OVERALL_END - OVERALL_START))
HOURS=$((OVERALL_TIME / 3600))
MINS=$(( (OVERALL_TIME % 3600) / 60 ))

echo "========================================"
echo "All RTLsim experiments completed!"
echo "Total time: ${HOURS}h ${MINS}m"
echo "Results in: $EVAL_DIR/results_rtlsim/"
echo "========================================"

# Quick summary
PASSED=$({ grep -rl 'status=PASSED' "$EVAL_DIR/results_rtlsim/" 2>/dev/null || true; } | wc -l)   # || true: no match must not end the script (pipefail)
FAILED=$({ grep -rl 'status=FAILED\|status=ERROR\|status=BUILD_FAILED' "$EVAL_DIR/results_rtlsim/" 2>/dev/null || true; } | wc -l)
TOTAL_RESULTS=$(find "$EVAL_DIR/results_rtlsim/" -name "*.txt" 2>/dev/null | wc -l)
echo "Results: $PASSED passed, $FAILED failed, $TOTAL_RESULTS total"
if [ "$SKIPPED_GROUPS" -gt 0 ]; then
    echo "ERROR: $SKIPPED_GROUPS group(s) were skipped (real-RTL config check or library build failed); their runs were not executed"
    exit 1
fi
