#!/usr/bin/env python3
"""Interim per-group flop activities over a calibration window (Oct 31). The counter file of a calibration run (gatesim_fpnew or
rtlsim_cal harness with VX_TRACE_START/VX_TRACE_STOP) has epochs 'trace_start' and 'trace_stop' (E <k> <tag> <core_ticks> lines,
C <k> <inst> <counter> <value> totals at each epoch). Window counters = stop - start; window busy cycles = core_ticks(stop) -
core_ticks(start) (windows are placed inside the busy kernel). Activities come from activity/core_dyn_prep.activities(), the same
function the production tables use. Output: one act.tsv line (config r benchmark busy group=alpha ...) per window.
Usage: calib_window_act.py <layout> <config> <r> <tag> <ctr file> [...]   (tag names the window, e.g. vecadd_1000_5000)"""
import sys, os, re, collections
H = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, os.path.join(os.path.dirname(H), 'activity'))
import core_dyn_prep as P
def epochs(path):
    tags, C, INFO = {}, collections.defaultdict(collections.Counter), {}
    for l in open(path):
        p = l.split()
        if not p: continue
        if p[0] == 'E': tags[p[2]] = (int(p[1]), int(p[3]))
        elif p[0] == 'C' and p[1] != 'F':
            pre = 'icache.' if '.icache.' in p[2] else ('dcache.' if '.dcache.' in p[2] else '')
            C[int(p[1])][pre + p[3]] += int(p[4])
        elif p[0] == 'I': INFO[p[1]] = dict(x.split('=', 1) for x in p[2:])
    return tags, C, INFO
def main():
    lay, cfg, r = sys.argv[1:4]; args = sys.argv[4:]
    for tag, path in zip(args[0::2], args[1::2]):
        tags, C, INFO = epochs(path)
        if 'trace_start' not in tags or 'trace_stop' not in tags: raise SystemExit(f'{path}: no trace_start/trace_stop epochs ({sorted(tags)})')
        (ks, ts), (ke, te) = tags['trace_start'], tags['trace_stop']
        busy = te - ts
        if busy <= 0: raise SystemExit(f'{path}: empty window')
        c = collections.Counter({k: C[ke][k] - C[ks].get(k, 0) for k in C[ke]})
        if any(v < 0 for v in c.values()): raise SystemExit(f'{path}: a counter decreased over the window')
        a = P.activities(c, INFO, lay, busy)
        print('\t'.join([cfg, r, tag, str(busy)] + [f'{k}={v:.6g}' for k, v in sorted(a.items())]))
if __name__ == '__main__': main()
