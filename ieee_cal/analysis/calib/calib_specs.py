#!/usr/bin/env python3
"""Calibration window list (Oct 31, plan F4): for one (config, r) prints calib_gate_job.sh specs <bench>:<opts>:<start>:<stop>.
Window: 2000 core cycles starting at min(busy/2, 300000) core ticks after reset (gate-level simulation runs ~900 cycles/s, so later
windows in long kernels cost hours; same capped-early-window idea as the earlier sweep). Timestamps = 2 x core ticks + 32 (the
harness's reset offset measured in the pilot: tick 9984 at timestamp 20000), so the window lies inside the busy kernel.
Usage: calib_specs.py <config> <r> <results_root> [bench ...]   (opts from the jobs_wave* files; default all 24 benchmarks)"""
import sys, os, glob, gzip
cfg, r, root = sys.argv[1:4]; want = sys.argv[4:]
E = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', 'eval_perf_swemu')
OPTS = {}
for f in glob.glob(os.path.join(E, 'jobs_wave*', '*.txt')):
    for l in open(f):
        p = l.split()
        if len(p) >= 5 and p[0] == cfg and p[1] == r: OPTS[p[2]] = p[3]
rows = glob.glob(os.path.join(root, '**', f'{cfg}_mem{r}_energy', '*_16x.ctr.gz'), recursive=True)
BUSY = {}
for p in rows:
    b = os.path.basename(p)[:-len('_16x.ctr.gz')]
    for l in gzip.open(p, 'rt'):
        if l.startswith('T busy_ticks'): BUSY[b] = int(l.split()[2])
for b in sorted(want or OPTS):
    if b not in OPTS or b not in BUSY: raise SystemExit(f'{cfg} {r} {b}: no job line or no accepted row')
    busy = BUSY[b]; ws = min(busy // 2, 300000)
    if ws < 100 or ws + 2000 > busy - 100: raise SystemExit(f'{cfg} {r} {b}: busy {busy} too short for a 2000-cycle window')
    print(f'{b}:{OPTS[b]}:{2 * ws + 32}:{2 * (ws + 2000) + 32}')
