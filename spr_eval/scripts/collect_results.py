#!/usr/bin/env python3
"""
Collect SPR results from all configurations and generate summary.
"""

import os
import json
import csv
from pathlib import Path
from datetime import datetime

SCRIPT_DIR = Path(__file__).parent
PROJECT_ROOT = SCRIPT_DIR.parent
RESULTS_DIR = PROJECT_ROOT / "results"

CONFIGS = [
    "baseline",
    "no_cache",
    "one_warp",
    "no_fpdiv",
    "no_intdiv",
    "no_numeric",
    "combined_pnm"
]

# Expected result files from OpenROAD flow
RESULT_FILES = {
    "area": "6_final_report.area",
    "timing": "6_final_report.timing",
    "power": "6_final_report.power",
}


def parse_area_report(filepath):
    """Parse OpenROAD area report."""
    # TODO: Implement actual parsing based on OpenROAD output format
    return {
        "total_area_um2": None,
        "cell_count": None,
        "utilization": None,
    }


def parse_timing_report(filepath):
    """Parse OpenSTA timing report."""
    # TODO: Implement actual parsing
    return {
        "critical_path_ns": None,
        "fmax_mhz": None,
        "wns": None,  # Worst Negative Slack
        "tns": None,  # Total Negative Slack
    }


def parse_power_report(filepath):
    """Parse OpenROAD power report."""
    # TODO: Implement actual parsing
    return {
        "dynamic_power_mw": None,
        "leakage_power_uw": None,
        "total_power_mw": None,
    }


def collect_config_results(config_name):
    """Collect results for a single configuration."""
    config_results_dir = RESULTS_DIR / config_name

    results = {
        "config": config_name,
        "status": "not_found",
    }

    if not config_results_dir.exists():
        return results

    # Check run info
    run_info = config_results_dir / "run_info.txt"
    if run_info.exists():
        results["status"] = "found"

    # Parse result files if they exist
    for report_type, filename in RESULT_FILES.items():
        filepath = config_results_dir / filename
        if filepath.exists():
            if report_type == "area":
                results.update(parse_area_report(filepath))
            elif report_type == "timing":
                results.update(parse_timing_report(filepath))
            elif report_type == "power":
                results.update(parse_power_report(filepath))

    return results


def calculate_deltas(results, baseline):
    """Calculate percentage changes relative to baseline."""
    if baseline.get("total_area_um2") is None:
        return results

    for key in ["total_area_um2", "dynamic_power_mw", "total_power_mw"]:
        if results.get(key) is not None and baseline.get(key) is not None:
            delta = ((results[key] - baseline[key]) / baseline[key]) * 100
            results[f"{key}_delta"] = f"{delta:+.1f}%"

    return results


def main():
    print("=" * 60)
    print("Vortex PNM SPR Results Collection")
    print("=" * 60)
    print(f"Results directory: {RESULTS_DIR}")
    print()

    all_results = []
    baseline_results = None

    for config in CONFIGS:
        results = collect_config_results(config)

        if config == "baseline":
            baseline_results = results
        elif baseline_results:
            results = calculate_deltas(results, baseline_results)

        all_results.append(results)
        print(f"  {config}: {results['status']}")

    # Save JSON summary
    json_output = RESULTS_DIR / "summary.json"
    with open(json_output, 'w') as f:
        json.dump({
            "timestamp": datetime.now().isoformat(),
            "configs": all_results,
        }, f, indent=2)
    print(f"\nJSON summary: {json_output}")

    # Save CSV summary
    csv_output = RESULTS_DIR / "summary.csv"
    if all_results:
        fieldnames = all_results[0].keys()
        with open(csv_output, 'w', newline='') as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(all_results)
        print(f"CSV summary: {csv_output}")

    # Print summary table
    print("\n" + "=" * 60)
    print("Summary Table")
    print("=" * 60)
    print(f"{'Config':<15} {'Status':<12} {'Area':<15} {'Power':<15} {'Fmax':<10}")
    print("-" * 60)
    for r in all_results:
        area = r.get('total_area_um2', 'N/A')
        power = r.get('total_power_mw', 'N/A')
        fmax = r.get('fmax_mhz', 'N/A')
        print(f"{r['config']:<15} {r['status']:<12} {str(area):<15} {str(power):<15} {str(fmax):<10}")

    print("\nNote: Run SPR flow first to populate results.")


if __name__ == "__main__":
    main()
