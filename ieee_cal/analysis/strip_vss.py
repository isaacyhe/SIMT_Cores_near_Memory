#!/usr/bin/env python3
# Oct 28: make the VDD-rail-only ASAP7 TT libs (cloud libs_vddonly/) used by floor_job.sh VDDONLY=1 and the core-switching job.
# Usage: strip_vss.py <in.lib[.gz]> <out.lib>
# Copy a liberty file, dropping every internal_power and leakage_power group whose related_pg_pin is VSS (keeps VDD groups and groups without a pg pin).
import sys, gzip, re
src, dst = sys.argv[1], sys.argv[2]
op = gzip.open if src.endswith('.gz') else open
txt = op(src, 'rt').read()
out = []; i = 0; kept = dropped = 0
pat = re.compile(r'(?:internal_power|leakage_power)\s*\(\s*\)\s*\{')
while True:
    m = pat.search(txt, i)
    if not m: out.append(txt[i:]); break
    s = m.start(); j = m.end(); depth = 1
    while depth:
        c = txt[j]
        if c == '{': depth += 1
        elif c == '}': depth -= 1
        j += 1
    block = txt[s:j]
    pg = re.search(r'related_pg_pin\s*:\s*"?(\w+)"?\s*;', block)
    # related_pg_pin of the group itself: must appear before any nested group
    first_nested = block.find('{', block.find('{') + 1)
    own = pg and (first_nested < 0 or pg.start() < first_nested)
    out.append(txt[i:s])
    if own and pg.group(1) == 'VSS':
        dropped += 1
        # also drop the leading whitespace line remainder
    else:
        out.append(block); kept += 1
    i = j
open(dst, 'w').write(''.join(out))
print(f"{src}: kept {kept} dropped {dropped}")
