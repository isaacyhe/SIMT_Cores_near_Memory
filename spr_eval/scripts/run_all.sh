#!/bin/bash
# Run SPR flow for all configurations
# Usage: ./run_all.sh [--parallel N] [--synth-only]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default: run sequentially
PARALLEL=1
SYNTH_ONLY=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --parallel|-p)
            PARALLEL="$2"
            shift 2
            ;;
        --synth-only)
            SYNTH_ONLY="--synth-only"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# All configurations (7 total)
CONFIGS=(
    "baseline"
    "no_cache"
    "one_warp"
    "no_fpdiv"
    "no_intdiv"
    "no_numeric"
    "combined_pnm"
)

echo "=========================================="
echo "Vortex PNM SPR Evaluation"
echo "=========================================="
echo "Configurations: ${#CONFIGS[@]}"
echo "Parallel jobs:  $PARALLEL"
echo "Results dir:    $PROJECT_ROOT/results/"
echo ""
echo "Configs: ${CONFIGS[*]}"
echo ""

START_TIME=$(date +%s)

if [ "$PARALLEL" -gt 1 ]; then
    echo "Running in parallel mode with $PARALLEL jobs..."
    printf '%s\n' "${CONFIGS[@]}" | xargs -P "$PARALLEL" -I {} "$SCRIPT_DIR/run_spr.sh" {} $SYNTH_ONLY
else
    echo "Running sequentially..."
    for config in "${CONFIGS[@]}"; do
        echo ""
        echo "=========================================="
        echo ">>> Processing: $config"
        echo "=========================================="
        "$SCRIPT_DIR/run_spr.sh" "$config" $SYNTH_ONLY
    done
fi

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo "=========================================="
echo "All SPR runs completed!"
echo "=========================================="
echo "Total time: ${ELAPSED}s"
echo "Results in: $PROJECT_ROOT/results/"
echo ""
echo "Run collect_results.py to generate summary CSV"
