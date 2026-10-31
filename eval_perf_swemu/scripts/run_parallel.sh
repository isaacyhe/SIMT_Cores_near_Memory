#!/bin/bash
# Run all experiments in parallel (grouped by CONFIG+MEM_RATIO to avoid simx rebuild conflicts)
# Usage: ./run_parallel.sh [num_parallel_jobs] [jobs_file]
# Example: ./run_parallel.sh 8 ../jobs_hw_only.txt
#
# Jobs are grouped by (config, mem_ratio) because simx must be rebuilt for:
# - Different MEM_CLOCK_RATIO values
# - Different RTL configs (L1_DISABLE, NUM_WARPS, etc.)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EVAL_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(dirname "$EVAL_DIR")"
VORTEX_DIR="$ROOT_DIR/vortex"
CONFIG_DIR="$EVAL_DIR/configs"

# Default parallelism and jobs file
NUM_JOBS=${1:-$(nproc)}
JOBS_FILE="${2:-$EVAL_DIR/jobs.txt}"

# Export RESULTS_TAG so it propagates to run_single_no_rebuild.sh via parallel/xargs
export RESULTS_TAG="${RESULTS_TAG:-}"

# Check prerequisites
if [ ! -f "$VORTEX_DIR/kernel/libvortex.a" ]; then
    echo "ERROR: libvortex.a not found. Building..."
    make -C "$VORTEX_DIR/kernel" || { echo "FATAL: Failed to build kernel library"; exit 1; }
fi

if [ ! -f "$JOBS_FILE" ]; then
    echo "Jobs file not found. Generating..."
    "$SCRIPT_DIR/generate_jobs.sh"
fi

TOTAL=$(wc -l < "$JOBS_FILE")
echo "Running $TOTAL experiments with $NUM_JOBS parallel jobs"
echo "NOTE: Jobs grouped by (CONFIG, MEM_RATIO) to avoid simx rebuild conflicts"
echo ""

# Get unique (config, ratio) pairs from jobs file (skip comments and blank lines)
PAIRS=($(awk '!/^[[:space:]]*#/ && NF>0 {print $1 ":" $2}' "$JOBS_FILE" | sort -u))

echo "Found ${#PAIRS[@]} unique (config, ratio) pairs"
echo ""

for pair in "${PAIRS[@]}"; do
    config="${pair%%:*}"
    ratio="${pair##*:}"

    echo "========================================"
    echo "=== CONFIG=$config, MEM_RATIO=$ratio ==="
    echo "========================================"

    # Read VX_CONFIG_OVERRIDE from config.mk
    VX_CONFIG_OVERRIDE=""
    if [ -f "$CONFIG_DIR/$config/config.mk" ]; then
        VX_CONFIG_OVERRIDE=$(grep -oP 'VX_CONFIG_OVERRIDE\s*=\s*\K.*' "$CONFIG_DIR/$config/config.mk" | tr -d '\n')
    fi

    # Build CONFIGS string for simx
    SIMX_CONFIGS="-DMEM_CLOCK_RATIO=${ratio}"
    if [ -n "$VX_CONFIG_OVERRIDE" ]; then
        SIMX_CONFIGS="$SIMX_CONFIGS $VX_CONFIG_OVERRIDE"
    fi

    echo "Building simx with CONFIGS: $SIMX_CONFIGS"
    make -C "$VORTEX_DIR/runtime/simx" VORTEX_HOME="$VORTEX_DIR" clean > /dev/null 2>&1
    if ! make -C "$VORTEX_DIR/runtime/simx" VORTEX_HOME="$VORTEX_DIR" CONFIGS="$SIMX_CONFIGS" PERF=1 > /dev/null 2>&1; then
        echo "ERROR: simx build failed for $config / $ratio! Skipping..."
        continue
    fi

    # Get jobs for this (config, ratio) pair (skip comments)
    PAIR_JOBS=$(awk -v c="$config" -v r="$ratio" '!/^[[:space:]]*#/ && $1==c && $2==r' "$JOBS_FILE")
    PAIR_COUNT=$(echo "$PAIR_JOBS" | wc -l)
    echo "Running $PAIR_COUNT benchmarks in parallel..."

    # Run all benchmarks for this pair in parallel using bash background jobs + wait
    # (xargs -P and GNU parallel can leave orphans or not wait properly)
    RUNNING_PIDS=()
    while IFS=' ' read -r cfg ratio bench opts; do
        [ -z "$cfg" ] && continue
        # Wait if at max parallelism
        while [ ${#RUNNING_PIDS[@]} -ge $NUM_JOBS ]; do
            for i in "${!RUNNING_PIDS[@]}"; do
                if ! kill -0 "${RUNNING_PIDS[$i]}" 2>/dev/null; then
                    unset 'RUNNING_PIDS[$i]'
                fi
            done
            RUNNING_PIDS=("${RUNNING_PIDS[@]}")
            [ ${#RUNNING_PIDS[@]} -ge $NUM_JOBS ] && sleep 1
        done
        "$SCRIPT_DIR/run_single_no_rebuild.sh" "$cfg" "$ratio" "$bench" "$opts" &
        RUNNING_PIDS+=($!)
    done <<< "$PAIR_JOBS"
    # Wait for ALL remaining jobs to complete before next group
    for pid in "${RUNNING_PIDS[@]}"; do
        wait "$pid" 2>/dev/null
    done

    echo ""
done

echo "========================================"
echo "All experiments completed!"
echo "Results in: $EVAL_DIR/results_simx/"
