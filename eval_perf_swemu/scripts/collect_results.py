#!/usr/bin/env python3
"""
Collect and aggregate results from all experiments.
Outputs CSV and paper-ready tables.
"""

import os
import sys
import csv
from pathlib import Path
from collections import defaultdict

SCRIPT_DIR = Path(__file__).parent
EVAL_DIR = SCRIPT_DIR.parent
RESULTS_DIR = EVAL_DIR / "results"
OUTPUT_CSV = EVAL_DIR / "results_summary.csv"

# Match paper Table I configs
CONFIGS = ["baseline", "no_cache", "one_warp", "no_fpdiv", "no_intdiv", "no_numeric", "combined_pnm"]
CONFIG_DISPLAY = {
    "baseline": "Baseline",
    "no_cache": "No-Cache",
    "one_warp": "1-Warp",
    "no_fpdiv": "No-FPDiv",
    "no_intdiv": "No-IntDiv",
    "no_numeric": "No-Div",
    "combined_pnm": "Minimal"
}

# Match paper Table II memory ratios
MEM_RATIOS = ["1.0", "0.6", "0.5", "0.4", "0.3", "0.2", "0.1"]

# Match paper Table V benchmarks by category
BENCHMARK_CATEGORIES = {
    "Basic Vector": ["vecadd", "saxpy", "dotproduct"],
    "Linear Algebra": ["sgemm3", "transpose"],
    "Stencil/Filter": ["conv3", "sfilter", "stencil", "guassian"],
    "Graph": ["bfs"],
    "ML/Clustering": ["kmeans", "nearn"],
    "Sparse": ["spmv"],
    "Scientific": ["blackscholes", "lbm"],
    "Parallel Patterns": ["psort", "psum"],
    "PNM-Oriented": ["histogram", "memcopy", "gather"]
}

# Workload classes for Table VII
WORKLOAD_CLASSES = {
    "Mem-Bound": ["vecadd", "saxpy", "dotproduct"],
    "Compute-Bound": ["sgemm3", "conv3", "blackscholes"],
    "Irregular": ["bfs", "spmv"],
    "PNM-Oriented": ["histogram", "memcopy", "gather"]
}

ALL_BENCHMARKS = [b for cat in BENCHMARK_CATEGORIES.values() for b in cat]


def parse_result_file(filepath):
    """Parse a single result file."""
    result = {}
    try:
        with open(filepath, 'r') as f:
            for line in f:
                if '=' in line:
                    key, value = line.strip().split('=', 1)
                    result[key] = value
    except FileNotFoundError:
        return None
    return result


def collect_all_results():
    """Collect results from all experiments."""
    results = []
    missing = []

    for config in CONFIGS:
        for mem_ratio in MEM_RATIOS:
            result_subdir = RESULTS_DIR / f"{config}_mem{mem_ratio}"
            for bench in ALL_BENCHMARKS:
                result_file = result_subdir / f"{bench}.txt"

                if result_file.exists():
                    data = parse_result_file(result_file)
                    if data:
                        results.append({
                            'config': config,
                            'mem_ratio': mem_ratio,
                            'benchmark': bench,
                            **data
                        })
                else:
                    missing.append(f"{config}/mem{mem_ratio}/{bench}")

    return results, missing


def write_csv(results, output_path):
    """Write results to CSV."""
    if not results:
        print("No results to write!")
        return

    all_keys = set()
    for r in results:
        all_keys.update(r.keys())

    priority_cols = ['config', 'mem_ratio', 'benchmark', 'cycles', 'instructions', 'ipc', 'status']
    columns = [c for c in priority_cols if c in all_keys]
    columns += sorted(all_keys - set(columns))

    with open(output_path, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=columns)
        writer.writeheader()
        writer.writerows(results)

    print(f"Wrote {len(results)} results to {output_path}")


def compute_speedups(results):
    """Compute speedup relative to baseline at same memory ratio."""
    # Index by (mem_ratio, benchmark) for baseline lookup
    baseline_cycles = {}
    for r in results:
        if r['config'] == 'baseline' and r.get('cycles'):
            try:
                baseline_cycles[(r['mem_ratio'], r['benchmark'])] = int(r['cycles'])
            except ValueError:
                pass

    # Compute speedup for each result
    speedups = []
    for r in results:
        key = (r['mem_ratio'], r['benchmark'])
        if key in baseline_cycles and r.get('cycles'):
            try:
                cycles = int(r['cycles'])
                if cycles > 0:
                    speedup = baseline_cycles[key] / cycles
                    speedups.append({
                        'config': r['config'],
                        'mem_ratio': r['mem_ratio'],
                        'benchmark': r['benchmark'],
                        'cycles': cycles,
                        'baseline_cycles': baseline_cycles[key],
                        'speedup': speedup
                    })
            except ValueError:
                pass

    return speedups


def find_breakeven_ratio(speedups, config, benchmarks):
    """Find memory ratio where config matches baseline (speedup >= 1.0)."""
    for ratio in MEM_RATIOS:
        ratio_speedups = [s['speedup'] for s in speedups
                        if s['config'] == config
                        and s['mem_ratio'] == ratio
                        and s['benchmark'] in benchmarks]
        if ratio_speedups:
            avg_speedup = sum(ratio_speedups) / len(ratio_speedups)
            if avg_speedup >= 1.0:
                return ratio
    return ">1.0"  # Never reaches breakeven


def generate_paper_tables(results, speedups):
    """Generate paper-ready tables."""
    output = []

    # ========== Table VII: Break-even ratios ==========
    output.append("\n" + "="*70)
    output.append("TABLE VII: Break-even memory latency ratios")
    output.append("="*70)
    output.append(f"{'Config':<12} {'Mem-Bound':<12} {'Compute-Bound':<14} {'Irregular':<12}")
    output.append("-"*50)

    for config in CONFIGS[1:]:  # Skip baseline
        row = [CONFIG_DISPLAY.get(config, config)]
        for wclass, benchmarks in WORKLOAD_CLASSES.items():
            breakeven = find_breakeven_ratio(speedups, config, benchmarks)
            row.append(str(breakeven))
        output.append(f"{row[0]:<12} {row[1]:<12} {row[2]:<14} {row[3]:<12}")

    # ========== Speedup by config and ratio (for Figs 8-10) ==========
    output.append("\n" + "="*70)
    output.append("SPEEDUP DATA (for figures)")
    output.append("="*70)

    for wclass, benchmarks in WORKLOAD_CLASSES.items():
        output.append(f"\n--- {wclass} Workloads ---")
        header = f"{'Config':<12}" + "".join([f"r={r:<6}" for r in MEM_RATIOS])
        output.append(header)
        output.append("-"*60)

        for config in CONFIGS:
            row = [CONFIG_DISPLAY.get(config, config)]
            for ratio in MEM_RATIOS:
                ratio_speedups = [s['speedup'] for s in speedups
                                if s['config'] == config
                                and s['mem_ratio'] == ratio
                                and s['benchmark'] in benchmarks]
                if ratio_speedups:
                    avg = sum(ratio_speedups) / len(ratio_speedups)
                    row.append(f"{avg:.2f}")
                else:
                    row.append("--")
            output.append(f"{row[0]:<12}" + "".join([f"{v:<8}" for v in row[1:]]))

    # ========== Per-benchmark cycles (raw data) ==========
    output.append("\n" + "="*70)
    output.append("RAW CYCLES BY BENCHMARK")
    output.append("="*70)

    for config in CONFIGS:
        output.append(f"\n--- {CONFIG_DISPLAY.get(config, config)} ---")
        header = f"{'Benchmark':<15}" + "".join([f"r={r:<10}" for r in MEM_RATIOS])
        output.append(header)

        for bench in ALL_BENCHMARKS:
            row = [bench]
            for ratio in MEM_RATIOS:
                matching = [r for r in results
                          if r['config'] == config
                          and r['mem_ratio'] == ratio
                          and r['benchmark'] == bench]
                if matching and matching[0].get('cycles'):
                    row.append(matching[0]['cycles'])
                else:
                    row.append("--")
            output.append(f"{row[0]:<15}" + "".join([f"{v:<10}" for v in row[1:]]))

    # ========== LaTeX table for Table VII ==========
    output.append("\n" + "="*70)
    output.append("LATEX TABLE VII")
    output.append("="*70)
    output.append(r"\begin{tabular}{lccc}")
    output.append(r"\toprule")
    output.append(r"Config & Mem-Bound & Compute-Bound & Irregular \\")
    output.append(r"\midrule")

    for config in CONFIGS[1:]:
        row = [CONFIG_DISPLAY.get(config, config)]
        for wclass, benchmarks in WORKLOAD_CLASSES.items():
            breakeven = find_breakeven_ratio(speedups, config, benchmarks)
            row.append(str(breakeven))
        output.append(f"{row[0]} & {row[1]} & {row[2]} & {row[3]} \\\\")

    output.append(r"\bottomrule")
    output.append(r"\end{tabular}")

    return "\n".join(output)


def print_summary(results, missing):
    """Print summary statistics."""
    total_expected = len(CONFIGS) * len(MEM_RATIOS) * len(ALL_BENCHMARKS)

    print(f"\n{'='*60}")
    print("RESULTS SUMMARY")
    print(f"{'='*60}")
    print(f"Completed: {len(results)} / {total_expected}")
    print(f"Missing:   {len(missing)} / {total_expected}")

    if missing and len(missing) <= 20:
        print(f"\nMissing experiments:")
        for m in missing[:20]:
            print(f"  - {m}")
        if len(missing) > 20:
            print(f"  ... and {len(missing) - 20} more")

    print(f"\nResults by config:")
    by_config = defaultdict(int)
    for r in results:
        by_config[r['config']] += 1
    for config in CONFIGS:
        expected = len(MEM_RATIOS) * len(ALL_BENCHMARKS)
        actual = by_config[config]
        status = "✓" if actual == expected else "✗"
        print(f"  {status} {CONFIG_DISPLAY.get(config, config)}: {actual}/{expected}")


def main():
    print("Collecting results from:", RESULTS_DIR)

    results, missing = collect_all_results()

    if results:
        write_csv(results, OUTPUT_CSV)

        speedups = compute_speedups(results)
        paper_tables = generate_paper_tables(results, speedups)

        # Write paper tables to file
        paper_output = EVAL_DIR / "paper_tables.txt"
        with open(paper_output, 'w') as f:
            f.write(paper_tables)
        print(f"Wrote paper tables to {paper_output}")

        # Also print to stdout
        print(paper_tables)

    print_summary(results, missing)

    return 0 if not missing else 1


if __name__ == "__main__":
    sys.exit(main())
