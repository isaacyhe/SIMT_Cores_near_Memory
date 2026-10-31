#!/bin/bash
# Generate all experiment jobs for parallel execution
# Each line is an independent job that can run in parallel

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EVAL_DIR="$(dirname "$SCRIPT_DIR")"
JOBS_FILE="$EVAL_DIR/jobs.txt"

# Configurations
CONFIGS=(baseline no_cache one_warp no_fpdiv no_intdiv no_numeric combined_pnm)

# Memory ratios (1.0=baseline, lower=faster memory/PNM)
# 0.5-0.6: On-Die PNM (~2× faster)
# 0.2-0.4: Near-Bank PNM (~2.5-5× faster)
# 0.1: Aggressive Near-Bank / UPMEM-like (~10× faster)
MEM_RATIOS=(1.0 0.6 0.5 0.4 0.3 0.2 0.1)

# Benchmarks (drop oclprintf)
BENCHMARKS=(vecadd saxpy dotproduct sgemm3 blackscholes guassian conv3 sfilter stencil transpose spmv lbm bfs kmeans nearn psort psum histogram memcopy gather)

# Clear previous jobs file
> "$JOBS_FILE"

# Generate all combinations
for config in "${CONFIGS[@]}"; do
    for mem_ratio in "${MEM_RATIOS[@]}"; do
        for bench in "${BENCHMARKS[@]}"; do
            echo "$config $mem_ratio $bench" >> "$JOBS_FILE"
        done
    done
done

TOTAL=$(wc -l < "$JOBS_FILE")
echo "Generated $TOTAL jobs in $JOBS_FILE"
echo ""
echo "Breakdown:"
echo "  Configs: ${#CONFIGS[@]}"
echo "  Memory ratios: ${#MEM_RATIOS[@]}"
echo "  Benchmarks: ${#BENCHMARKS[@]}"
echo "  Total: ${#CONFIGS[@]} × ${#MEM_RATIOS[@]} × ${#BENCHMARKS[@]} = $TOTAL"
