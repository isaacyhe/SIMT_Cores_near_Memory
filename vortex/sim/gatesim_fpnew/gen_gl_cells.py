#!/usr/bin/env python3
# ============================================================================
# Generate Verilator-compatible behavioral Verilog for the ASAP7 combinational
# cells used in the baseline gate netlist, from the liberty `function` attribute
# (ground truth -> no hand-derivation error). Sequential cells (DFFHQNx1/2/3)
# come from ORFS dff.v; physical cells (FILLER/DECAP/TAPCELL) from empty.v.
#
# Liberty function operators -> Verilog:  *->&  +->|  !->~  ^->^  '(postfix)->~
# Usage: gen_gl_cells.py <celltypes.txt> <out.v>
# ============================================================================
import sys, re, gzip, glob, os

LIBDIR = os.environ["ASAP7_NLDM"]   # gatesim_fpnew: the TT liberty dir passed in
# combinational liberty families (RVT, TT corner)
LIBS = glob.glob(f"{LIBDIR}/asap7sc7p5t_*_RVT_TT_nldm_*.lib.gz")

# cells we DON'T generate here (handled by dff.v / empty.v)
SKIP_RE = re.compile(r'^(DFFHQN|DFF|SDFF|FILLER|DECAP|TAPCELL|LATCH|ICG)')

def read_lib(path):
    op = gzip.open if path.endswith(".gz") else open
    with op(path, "rt", errors="replace") as f:
        return f.read()

def parse_cells(text):
    """Return {cellname: {'inputs':[...], 'outputs':[(pin,func)...]}}."""
    cells = {}
    # find 'cell (NAME) {' then walk braces to its matching close
    i = 0
    pat = re.compile(r'\bcell\s*\(\s*([A-Za-z0-9_]+)\s*\)\s*\{')
    for m in pat.finditer(text):
        name = m.group(1)
        # extract balanced block
        depth = 1; j = m.end()
        while j < len(text) and depth:
            c = text[j]
            if c == '{': depth += 1
            elif c == '}': depth -= 1
            j += 1
        block = text[m.end():j-1]
        cells[name] = parse_pins(block)
    return cells

def parse_pins(block):
    inputs, outputs = [], []
    pinpat = re.compile(r'\bpin\s*\(\s*([A-Za-z0-9_]+)\s*\)\s*\{')
    for pm in pinpat.finditer(block):
        pname = pm.group(1)
        depth = 1; j = pm.end()
        while j < len(block) and depth:
            c = block[j]
            if c == '{': depth += 1
            elif c == '}': depth -= 1
            j += 1
        pb = block[pm.end():j-1]
        dirn = re.search(r'\bdirection\s*:\s*([a-z]+)\s*;', pb)
        func = re.search(r'\bfunction\s*:\s*"([^"]*)"\s*;', pb)
        if dirn and dirn.group(1) == 'input':
            inputs.append(pname)
        elif dirn and dirn.group(1) == 'output':
            outputs.append((pname, func.group(1) if func else None))
    return {'inputs': inputs, 'outputs': outputs}

def lib_func_to_verilog(fn):
    # operators: * -> &, + -> |, ! -> ~, ^ stays. postfix ' -> not (rare)
    # handle postfix apostrophe: X' -> (~X)
    fn = re.sub(r'([A-Za-z0-9_]+)\s*\'', r'(~\1)', fn)
    fn = fn.replace('*', '&').replace('+', '|').replace('!', '~')
    return fn.strip()

def main():
    celltypes_file, outv = sys.argv[1], sys.argv[2]
    used = []
    with open(celltypes_file) as f:
        for line in f:
            parts = line.split()
            if not parts: continue
            cell = parts[-1]
            if not cell.endswith("_ASAP7_75t_R"): continue
            if SKIP_RE.match(cell): continue
            used.append(cell)
    used = sorted(set(used))

    # build global cell dict from all combinational libs
    allcells = {}
    for lib in LIBS:
        allcells.update(parse_cells(read_lib(lib)))

    out = ["// AUTO-GENERATED behavioral models from ASAP7 liberty `function` (RVT TT).",
           "// For Verilator gate-level activity sim (Sweep A). Do not edit by hand.",
           "`timescale 1ns/1ps"]
    missing, done = [], []
    for cell in used:
        c = allcells.get(cell)
        if not c or not c['outputs']:
            missing.append(cell); continue
        ports = c['inputs'] + [p for p, _ in c['outputs']]
        out.append(f"module {cell} ({', '.join(ports)});")
        for p in c['inputs']:
            out.append(f"  input {p};")
        body = []
        ok = True
        for pin, fn in c['outputs']:
            out.append(f"  output {pin};")
            if fn is None:
                ok = False; break
            body.append(f"  assign {pin} = {lib_func_to_verilog(fn)};")
        if not ok:
            missing.append(cell); out = out[:-(len(c['inputs'])+len(c['outputs'])+1)]; continue
        out.extend(body)
        out.append("endmodule")
        done.append(cell)

    with open(outv, "w") as f:
        f.write("\n".join(out) + "\n")
    print(f"generated {len(done)} cells -> {outv}")
    if missing:
        print(f"MISSING ({len(missing)}): {missing}")
    else:
        print("MISSING: none")

if __name__ == "__main__":
    main()
