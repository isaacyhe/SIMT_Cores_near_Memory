#!/usr/bin/env python3
"""
Estimate power and area from Yosys synthesis results.
Uses ASAP7 7nm cell characteristics for estimation.

Usage: python3 estimate_power_area.py [results_dir]
"""

import os
import re
import sys
import glob
import csv
from pathlib import Path

# ASAP7 7nm cell characteristics (approximate values)
# Area in um^2, power in uW at 500MHz (2ns clock period)
ASAP7_CELL_DATA = {
    # Combinational cells
    '$_NOT_':      {'area': 0.0504, 'power': 0.05},
    '$_AND_':      {'area': 0.0756, 'power': 0.08},
    '$_OR_':       {'area': 0.0756, 'power': 0.08},
    '$_XOR_':      {'area': 0.1008, 'power': 0.12},
    '$_NAND_':     {'area': 0.0756, 'power': 0.07},
    '$_NOR_':      {'area': 0.0756, 'power': 0.07},
    '$_XNOR_':     {'area': 0.1008, 'power': 0.12},
    '$_MUX_':      {'area': 0.1260, 'power': 0.15},
    '$_AOI3_':     {'area': 0.1008, 'power': 0.10},
    '$_OAI3_':     {'area': 0.1008, 'power': 0.10},
    '$_AOI4_':     {'area': 0.1260, 'power': 0.12},
    '$_OAI4_':     {'area': 0.1260, 'power': 0.12},

    # Sequential cells (flip-flops)
    '$_DFF_P_':    {'area': 0.5040, 'power': 0.50},
    '$_DFF_N_':    {'area': 0.5040, 'power': 0.50},
    '$_DFF_PP0_':  {'area': 0.6300, 'power': 0.55},
    '$_DFF_PP1_':  {'area': 0.6300, 'power': 0.55},
    '$_DFF_PN0_':  {'area': 0.6300, 'power': 0.55},
    '$_DFF_PN1_':  {'area': 0.6300, 'power': 0.55},
    '$_DFFE_PP_':  {'area': 0.6300, 'power': 0.60},
    '$_DFFE_PN_':  {'area': 0.6300, 'power': 0.60},
    '$_SDFF_PP0_': {'area': 0.7560, 'power': 0.65},
    '$_SDFF_PP1_': {'area': 0.7560, 'power': 0.65},

    # Memory cells (per bit)
    'memory':      {'area': 0.0200, 'power': 0.02},  # SRAM per bit
}

# Default values for unknown cells
DEFAULT_CELL = {'area': 0.1000, 'power': 0.10}


def parse_yosys_log(log_path):
    """Parse Yosys log file for statistics."""
    stats = {
        'cells': {},
        'total_cells': 0,
        'wires': 0,
        'wire_bits': 0,
        'memories': 0,
        'memory_bits': 0,
    }

    if not os.path.exists(log_path):
        print(f"  Warning: {log_path} not found")
        return stats

    with open(log_path, 'r') as f:
        content = f.read()

    # Find the statistics section
    stats_match = re.search(r'Printing statistics\.(.*?)(?=\d+\.\s|\Z)', content, re.DOTALL)
    if not stats_match:
        # Try alternative format
        stats_match = re.search(r'=== Vortex ===(.*?)(?=End of script|\Z)', content, re.DOTALL)

    if stats_match:
        stats_section = stats_match.group(1)

        # Parse number of wires (format: "  75082 wires")
        wires_match = re.search(r'^\s*(\d+)\s+wires\s*$', stats_section, re.MULTILINE)
        if wires_match:
            stats['wires'] = int(wires_match.group(1))

        # Parse wire bits
        wire_bits_match = re.search(r'^\s*(\d+)\s+wire bits\s*$', stats_section, re.MULTILINE)
        if wire_bits_match:
            stats['wire_bits'] = int(wire_bits_match.group(1))

        # Parse memories
        mem_match = re.search(r'^\s*(\d+)\s+memories\s*$', stats_section, re.MULTILINE)
        if mem_match:
            stats['memories'] = int(mem_match.group(1))

        # Parse memory bits
        mem_bits_match = re.search(r'^\s*(\d+)\s+memory bits\s*$', stats_section, re.MULTILINE)
        if mem_bits_match:
            stats['memory_bits'] = int(mem_bits_match.group(1))

        # Parse total cells (format: "  1152480 cells")
        cells_match = re.search(r'^\s*(\d+)\s+cells\s*$', stats_section, re.MULTILINE)
        if cells_match:
            stats['total_cells'] = int(cells_match.group(1))

        # Parse individual cell types (format: "   72280   $_AND_")
        # Yosys format is: count cell_type (number first, then $ prefixed name)
        cell_pattern = re.compile(r'^\s*(\d+)\s+(\$[\w]+)\s*$', re.MULTILINE)
        for match in cell_pattern.finditer(stats_section):
            count = int(match.group(1))
            cell_type = match.group(2)
            stats['cells'][cell_type] = count

    return stats


def estimate_area_power(stats):
    """Estimate area and power from cell statistics."""
    total_area = 0.0
    total_power = 0.0

    # Calculate from individual cells
    for cell_type, count in stats['cells'].items():
        cell_data = ASAP7_CELL_DATA.get(cell_type, DEFAULT_CELL)
        total_area += count * cell_data['area']
        total_power += count * cell_data['power']

    # Add memory contribution
    if stats['memory_bits'] > 0:
        mem_data = ASAP7_CELL_DATA['memory']
        total_area += stats['memory_bits'] * mem_data['area']
        total_power += stats['memory_bits'] * mem_data['power']

    # If no cell breakdown, estimate from total cells
    if not stats['cells'] and stats['total_cells'] > 0:
        total_area = stats['total_cells'] * DEFAULT_CELL['area']
        total_power = stats['total_cells'] * DEFAULT_CELL['power']

    # Compute mapped cell count (sum of individually-typed cells)
    mapped_cells = sum(stats['cells'].values())

    return {
        'area_um2': total_area,
        'area_mm2': total_area / 1e6,
        'power_uW': total_power,
        'power_mW': total_power / 1e3,
        'mapped_cells': mapped_cells,
    }


def process_config(build_dir, config_name):
    """Process a single configuration."""
    log_path = os.path.join(build_dir, 'yosys.log')

    print(f"\n=== {config_name} ===")

    stats = parse_yosys_log(log_path)
    estimates = estimate_area_power(stats)

    result = {
        'config': config_name,
        'total_cells': stats['total_cells'],
        'mapped_cells': estimates['mapped_cells'],
        'wires': stats['wires'],
        'wire_bits': stats['wire_bits'],
        'memories': stats['memories'],
        'memory_bits': stats['memory_bits'],
        'area_um2': estimates['area_um2'],
        'area_mm2': estimates['area_mm2'],
        'power_uW': estimates['power_uW'],
        'power_mW': estimates['power_mW'],
    }

    print(f"  Total Cells:  {stats['total_cells']:,}")
    print(f"  Mapped Cells: {estimates['mapped_cells']:,}")
    print(f"  Wires:        {stats['wires']:,}")
    print(f"  Wire Bits:    {stats['wire_bits']:,}")
    print(f"  Memories:     {stats['memories']:,}")
    print(f"  Memory Bits:  {stats['memory_bits']:,}")
    print(f"  Est. Area:    {estimates['area_um2']:.2f} um² ({estimates['area_mm2']:.4f} mm²)")
    print(f"  Est. Power:   {estimates['power_uW']:.2f} uW ({estimates['power_mW']:.4f} mW) @ 500MHz")

    # Print cell breakdown if available
    if stats['cells']:
        print(f"  Cell Types:   {len(stats['cells'])}")
        # Top 5 cell types
        sorted_cells = sorted(stats['cells'].items(), key=lambda x: x[1], reverse=True)[:5]
        for cell, count in sorted_cells:
            print(f"    {cell}: {count:,}")

    return result


def main():
    # Determine project root
    script_dir = Path(__file__).parent
    project_root = script_dir.parent

    if len(sys.argv) > 1:
        project_root = Path(sys.argv[1])

    build_dir = project_root / 'build'
    results_dir = project_root / 'results'

    print("=" * 60)
    print("Vortex PNM - Power & Area Estimation from Synthesis")
    print("=" * 60)
    print(f"Build directory: {build_dir}")
    print(f"Using ASAP7 7nm cell characteristics")

    # Find all configurations
    configs = sorted([d.name for d in build_dir.iterdir() if d.is_dir()])

    if not configs:
        print("No configurations found!")
        sys.exit(1)

    print(f"Found {len(configs)} configurations: {', '.join(configs)}")

    # Process each configuration
    all_results = []
    for config in configs:
        config_build = build_dir / config
        result = process_config(str(config_build), config)
        all_results.append(result)

    # Generate summary CSV
    csv_path = results_dir / 'synthesis_estimates.csv'
    results_dir.mkdir(parents=True, exist_ok=True)

    with open(csv_path, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=[
            'config', 'total_cells', 'mapped_cells', 'wires', 'wire_bits',
            'memories', 'memory_bits', 'area_um2', 'area_mm2',
            'power_uW', 'power_mW'
        ])
        writer.writeheader()
        writer.writerows(all_results)

    print(f"\n{'=' * 60}")
    print("Summary saved to:", csv_path)
    print("=" * 60)

    # Print comparison table
    if len(all_results) > 1:
        baseline = next((r for r in all_results if r['config'] == 'baseline'), all_results[0])

        print("\n=== Relative Comparison (vs baseline) ===")
        print(f"{'Config':<15} {'Cells':>12} {'Area':>12} {'Power':>12}")
        print("-" * 55)

        for r in all_results:
            base_cells = baseline['total_cells'] or baseline['mapped_cells']
            r_cells = r['total_cells'] or r['mapped_cells']
            if base_cells > 0:
                cell_ratio = r_cells / base_cells
                area_ratio = r['area_um2'] / baseline['area_um2'] if baseline['area_um2'] > 0 else 0
                power_ratio = r['power_uW'] / baseline['power_uW'] if baseline['power_uW'] > 0 else 0
                print(f"{r['config']:<15} {cell_ratio:>11.2f}x {area_ratio:>11.2f}x {power_ratio:>11.2f}x")
            else:
                print(f"{r['config']:<15} {'N/A':>12} {'N/A':>12} {'N/A':>12}")


if __name__ == '__main__':
    main()
