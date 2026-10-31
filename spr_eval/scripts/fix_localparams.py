#!/usr/bin/env python3
"""
Fix sv2v cross-scope localparam references for Yosys.

The issue: sv2v generates localparams with hierarchical names like
_bbase_714AA_xxx that are defined in multiple scopes with different values.
Yosys can't resolve which scope to use for cross-scope references.

Solution: Parse the file, track localparam definitions by scope,
and inline values where there are cross-scope references.
"""

import re
import sys
from collections import defaultdict

def fix_localparams(content):
    """
    Fix cross-scope localparam references by tracking scope hierarchy
    and inlining values.
    """
    lines = content.split('\n')

    # First pass: collect all localparam definitions with their scopes
    # Track scope by indentation level (simple heuristic)
    param_defs = {}  # name -> [(scope_level, value)]

    for i, line in enumerate(lines):
        # Match localparam definition
        match = re.match(r'^(\t*)localparam\s+(\w+)\s*=\s*(.+?)\s*;', line)
        if match:
            indent, name, value = match.groups()
            scope_level = len(indent)
            if name not in param_defs:
                param_defs[name] = []
            param_defs[name].append((scope_level, value.strip(), i))

    # Find params that are defined multiple times (cross-scope issue)
    multi_scope_params = {k: v for k, v in param_defs.items() if len(v) > 1}

    print(f"Found {len(multi_scope_params)} multi-scope parameters")
    for name in list(multi_scope_params.keys())[:5]:
        print(f"  {name}: {len(multi_scope_params[name])} definitions")

    # Second pass: for each reference to a multi-scope param,
    # try to resolve it based on scope level, or use the "0" value as fallback
    fixed_lines = []

    for i, line in enumerate(lines):
        # Skip if this is a localparam definition itself
        if re.match(r'^\t*localparam\s+\w+\s*=', line):
            fixed_lines.append(line)
            continue

        modified = line

        # Look for references to multi-scope params
        for name in multi_scope_params:
            if name in modified:
                # Find the definition with value "0" or the first one
                definitions = multi_scope_params[name]

                # Prefer value "0" if it exists, otherwise first definition
                value = None
                for scope_level, val, line_num in definitions:
                    if val == '0':
                        value = '0'
                        break

                if value is None:
                    # Use the definition closest to (before) this line
                    for scope_level, val, line_num in reversed(definitions):
                        if line_num < i:
                            value = val
                            break

                    if value is None:
                        value = definitions[0][1]

                # Replace the parameter reference with its value
                # Only if it's used in an expression, not in a definition
                pattern = rf'\b{re.escape(name)}\b'
                if re.search(pattern, modified):
                    modified = re.sub(pattern, value, modified)

        fixed_lines.append(modified)

    return '\n'.join(fixed_lines)


def fix_localparams_v2(content):
    """
    Alternative approach: Remove cross-scope parameter references entirely
    by inlining the expression at definition point.
    """
    lines = content.split('\n')

    # Collect all _bbase_ and similar parameters
    bbase_params = {}

    for i, line in enumerate(lines):
        # Match localparam _bbase_* = expression
        match = re.match(r'^(\t*)localparam\s+(_bbase_\w+)\s*=\s*(.+?)\s*;', line)
        if match:
            indent, name, value = match.groups()
            # Store the latest definition for each parameter
            bbase_params[name] = value.strip()

    print(f"Found {len(bbase_params)} _bbase_ parameters")

    # Now inline all references
    fixed_lines = []

    for line in lines:
        modified = line

        # Replace _bbase_ parameter references with their values
        for name, value in bbase_params.items():
            if name in modified:
                # Only replace if it's a reference, not the definition
                if not re.match(rf'^\t*localparam\s+{re.escape(name)}\s*=', modified):
                    modified = re.sub(rf'\b{re.escape(name)}\b', f'({value})', modified)

        fixed_lines.append(modified)

    return '\n'.join(fixed_lines)


def fix_scope_params_aggressive(content):
    """
    Most aggressive fix: Rename all parameters to be globally unique
    by prefixing with line number.
    """
    lines = content.split('\n')

    # Find all problematic _bbase_ parameters
    bbase_defs = []

    for i, line in enumerate(lines):
        match = re.match(r'^(\t*)localparam\s+(_bbase_\w+)\s*=\s*(.+?)\s*;', line)
        if match:
            indent, name, value = match.groups()
            bbase_defs.append((i, name, value))

    if not bbase_defs:
        print("No _bbase_ parameters found")
        return content

    print(f"Found {len(bbase_defs)} _bbase_ definitions")

    # For each definition, make it unique by renaming to _bbaseL{lineno}_{rest}
    renames = {}  # old_name -> new_name (per line range)

    # Group by base name
    by_name = defaultdict(list)
    for lineno, name, value in bbase_defs:
        by_name[name].append((lineno, value))

    # For each multi-definition param, rename all occurrences
    for name, defs in by_name.items():
        if len(defs) > 1:
            for idx, (lineno, value) in enumerate(defs):
                new_name = f"_bbaseL{lineno}_{name[7:]}"  # Skip "_bbase_" prefix
                renames[(name, lineno)] = new_name

    # Apply renames (simple approach: process line by line)
    fixed_lines = []
    current_scope_renames = {}  # Track which rename applies in current scope

    for i, line in enumerate(lines):
        modified = line

        # Check if this line defines a _bbase_ param
        match = re.match(r'^(\t*)localparam\s+(_bbase_\w+)\s*=\s*(.+?)\s*;', line)
        if match:
            indent, name, value = match.groups()
            key = (name, i)
            if key in renames:
                new_name = renames[key]
                modified = re.sub(rf'\b{re.escape(name)}\b', new_name, modified, count=1)
                # Track this rename for the scope
                current_scope_renames[name] = new_name
        else:
            # Apply current scope renames to references
            for old_name, new_name in current_scope_renames.items():
                if old_name in modified:
                    modified = re.sub(rf'\b{re.escape(old_name)}\b', new_name, modified)

        # Simple scope tracking (end of generate/begin block clears renames)
        if re.search(r'\bend\b', line):
            # Clear some renames when leaving scope
            pass

        fixed_lines.append(modified)

    return '\n'.join(fixed_lines)


def simplify_to_zero(content):
    """
    Simplest fix: Replace all _bbase_ and _mbase_ references with 0.
    This works for synthesis when the exact values don't affect correctness.
    Also fixes RHS of localparam definitions that reference cross-scope params.
    """
    lines = content.split('\n')
    fixed_lines = []

    # Match both _bbase_ and _mbase_ patterns
    param_pattern = re.compile(r'\b(_[bm]base_\w+)\b')

    count = 0
    for line in lines:
        # Check if this is a localparam definition
        def_match = re.match(r'^(\t*localparam\s+)(\w+)(\s*=\s*)(.+?)(;.*)$', line)
        if def_match:
            prefix, name, eq, value, suffix = def_match.groups()
            # If the value contains a cross-scope reference, replace it
            if param_pattern.search(value):
                original_value = value
                value = param_pattern.sub('0', value)
                if value != original_value:
                    count += 1
                    line = f"{prefix}{name}{eq}{value}{suffix}"
            fixed_lines.append(line)
            continue

        # Replace references in other lines
        if param_pattern.search(line):
            original = line
            line = param_pattern.sub('0', line)
            if line != original:
                count += 1

        fixed_lines.append(line)

    print(f"Replaced {count} _bbase_/_mbase_ references with 0")
    return '\n'.join(fixed_lines)


def fix_genvar_indices(content):
    """
    Fix hierarchical references that use genvar indices.
    For single-core configs, replace cluster_id, socket_id, core_id, issue_id with 0.
    Only match whole words to avoid partial matches.
    """
    # Common genvar names used in hierarchical references
    genvars = ['cluster_id', 'socket_id', 'core_id', 'issue_id', 'unit_id', 'warp_id']

    count = 0
    for gv in genvars:
        # Match genvar used as index in hierarchical path: [genvar_name]
        # Use word boundaries to avoid partial matches like issue_idx
        # Pattern: [...genvar...] where genvar is a whole word
        pattern = rf'\[([^\]]*)\b{gv}\b([^\]]*)\]'
        matches = re.findall(pattern, content)
        if matches:
            # Replace genvar with 0 in these contexts
            content = re.sub(pattern, r'[\g<1>0\g<2>]', content)
            count += len(matches)

    print(f"Replaced {count} genvar index references with 0")
    return content


def remove_hierarchical_refs(content):
    """
    Remove or simplify problematic hierarchical references.
    For synthesis estimation, comment out lines with such references.
    """
    lines = content.split('\n')
    fixed_lines = []

    # Pattern to match any line with hierarchical reference Vortex.g_clusters[...]
    hier_pattern = re.compile(r'Vortex\.g_clusters\[')

    count = 0
    for line in lines:
        if hier_pattern.search(line):
            # Comment out lines containing hierarchical references
            indent = len(line) - len(line.lstrip())
            line = ' ' * indent + '// HIER_REF: ' + line.strip()
            count += 1

        fixed_lines.append(line)

    print(f"Commented out {count} lines with hierarchical references")
    return '\n'.join(fixed_lines)


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 fix_localparams.py input.v [output.v] [--mode=MODE]")
        print("Modes: inline (default), zero, rename, full (zero + genvar)")
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 and not sys.argv[2].startswith('--') else input_file

    mode = "inline"
    for arg in sys.argv:
        if arg.startswith('--mode='):
            mode = arg.split('=')[1]

    print(f"Reading: {input_file}")
    with open(input_file, 'r') as f:
        content = f.read()

    print(f"Mode: {mode}")

    if mode == "zero":
        fixed = simplify_to_zero(content)
    elif mode == "rename":
        fixed = fix_scope_params_aggressive(content)
    elif mode == "full":
        # Apply both zero and genvar fixes
        fixed = simplify_to_zero(content)
        fixed = fix_genvar_indices(fixed)
    elif mode == "aggressive":
        # Apply all fixes including hierarchical reference removal
        fixed = simplify_to_zero(content)
        fixed = fix_genvar_indices(fixed)
        fixed = remove_hierarchical_refs(fixed)
    else:  # inline
        fixed = fix_localparams_v2(content)

    print(f"Writing: {output_file}")
    with open(output_file, 'w') as f:
        f.write(fixed)

    print("Done!")


if __name__ == '__main__':
    main()
