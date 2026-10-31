#!/usr/bin/env python3
"""core_dyn.tsv from the core_dyn_job.sh logs (Oct 30). Interim, uncalibrated (calibrated=0).
Per run: P_dyn = (Sequential + Combinational + Clock totals)(run) - (same)(ZERO), where ZERO is the same session with every flop
group at activity 0. The Macro row is left out on purpose: the FakeRAM placeholder libs give macro input pins internal power, so the
Macro row rises with flop activity, and SRAM energy comes from sram_energy.tsv instead (counting it here would double count).
E_core_dyn = P_dyn x busy_ticks x period (activities are per core clock period; period from floors_vddonly.tsv, which energy.py
checks against each row's core_period_ps). The Macro rise is written as a diagnostic column only.
Usage: core_dyn_collect.py <log> ...  -> ../core_dyn.tsv"""
import sys, os, csv, re
H = os.path.dirname(os.path.abspath(__file__)); A = os.path.dirname(H)
PER = {r['layout']: float(r['period']) * 1e-12 for r in csv.DictReader((l for l in open(os.path.join(A, 'floors_vddonly.tsv')) if not l.startswith('#')), delimiter='\t')}
GROUPS = ('Sequential', 'Combinational', 'Clock', 'Macro')
SIGN = {}   # signoff.tsv: the period and odb each layout's OpenSTA session must have used
GRID = {'2000', '2500', '3000', '4000', '5000', '6000', '10000'}   # exact strings, as signoff_check.awk
try: SIGN_LINES = open(os.path.join(A, 'signoff.tsv'), newline='', encoding='ascii').readlines()
except UnicodeDecodeError as e: raise SystemExit(f'signoff.tsv: non-ASCII content ({e})')
for i, l in enumerate(SIGN_LINES, 1):   # signoff_check.awk's row rules; stricter only in two fail-closed ways: the whole file must be ASCII
                                        # (comments and evidence too) and every layout must have a floor
    f = l.rstrip('\n').split('\t')
    if '\r' in l: raise SystemExit(f'signoff.tsv line {i}: CR')
    if l.startswith('#') or f[0] == 'layout': continue
    if (len(f) < 3 or not re.fullmatch(r'[A-Za-z0-9_]+', f[0]) or f[1] not in GRID
            or not re.fullmatch(r'[A-Za-z0-9_.]+\.odb', f[2]) or f[0] in SIGN): raise SystemExit(f'signoff.tsv line {i} malformed: {l!r}')
    SIGN[f[0]] = (int(f[1]), f[2])
missing = sorted(set(SIGN) - set(PER))
if missing: raise SystemExit(f'signoff.tsv layouts not in floors_vddonly.tsv: {missing}')
def session(path, lay):
    # the Tcl the job wrote next to its log (copied with it) and, in newer logs, the INFO line must match signoff.tsv
    want = SIGN.get(lay, (2000, '6_final.odb')); tcl = path[:-4] + '.tcl'
    if not os.path.exists(tcl): raise SystemExit(f'{path}: no {os.path.basename(tcl)} next to it (needed to check period and odb)')
    t = open(tcl).read()
    per = re.findall(r'create_clock -name clk -period (\d+)\s', t); odb = re.findall(r'read_db \S*/([^/\s]+)\s', t)
    if per != [str(want[0])] or odb != [want[1]]: raise SystemExit(f'{path}: session period {per} odb {odb} != signoff.tsv {want}')
    info = re.findall(r'^INFO (\S+) period=(\d+) odb=(\S+)$', open(path).read(), re.M)
    if 'puts "INFO' in t and len(info) != 1: raise SystemExit(f'{path}: its Tcl prints INFO but the log has {len(info)} INFO lines')
    for n, p, o in info:
        if (n, int(p), o) != (lay, *want): raise SystemExit(f'{path}: INFO {n} {p} {o} != {lay} signoff.tsv {want}')
    if abs(PER[lay] - want[0] * 1e-12) > 1e-18: raise SystemExit(f'{lay}: floors_vddonly period {PER[lay]} != signoff.tsv {want[0]} ps')
def reports(path):
    cur = None; rep = {}
    for l in open(path):
        if l.startswith('=== RUN'):
            if cur is not None: yield cur, rep
            cur = l.split()[2:]; rep = {}
        elif cur is not None:
            p = l.split()
            if p and p[0] in GROUPS and len(p) >= 5: rep[p[0]] = float(p[4])
    if cur is not None: yield cur, rep
out = []; seen = set()
for path in sys.argv[1:]:
    lay = os.path.basename(path)[:-4]
    if lay not in PER: raise SystemExit(f'{path}: layout {lay} not in floors_vddonly.tsv')
    if 'COREDYN_DONE' not in open(path).read(): raise SystemExit(f'{path}: incomplete (no COREDYN_DONE)')
    session(path, lay)
    zero = None; n = 0
    for hdr, rep in reports(path):
        if set(rep) != set(GROUPS): raise SystemExit(f'{path}: report {hdr} lacks rows {set(GROUPS) - set(rep)}')
        if hdr == ['ZERO']:
            if zero is not None: raise SystemExit(f'{path}: two ZERO reports')
            zero = rep; continue
        if zero is None: raise SystemExit(f'{path}: run report before ZERO')
        cfg, r, bench, busy = hdr; busy = int(busy)
        if (cfg, r, bench) in seen: raise SystemExit(f'{path}: duplicate run {cfg} {r} {bench}')
        seen.add((cfg, r, bench))
        if abs(rep['Clock'] - zero['Clock']) > 1e-12: raise SystemExit(f'{path}: clock power differs from ZERO in {hdr}')
        p = sum(rep[g] - zero[g] for g in ('Sequential', 'Combinational', 'Clock'))
        if p < 0: raise SystemExit(f'{path}: negative switching power in {hdr}')
        out.append((cfg, r, bench, lay, busy, p, rep['Macro'] - zero['Macro'], p * busy * PER[lay])); n += 1
    print(f'{lay}: {n} runs')
with open(os.path.join(A, 'core_dyn.tsv'), 'w') as f:
    f.write('# core_dyn_collect.py: interim uncalibrated core switching (flop-anchored OpenSTA propagation, VDD-only TT libs); Macro rise excluded\n')
    f.write('config\tr\tbenchmark\tlayout\tbusy_ticks\tp_dyn_W\tmacro_rise_W_excluded\te_core_dyn_J\tcalibrated\n')
    for row in sorted(out): f.write('\t'.join(map(str, row[:5])) + f'\t{row[5]:.6e}\t{row[6]:.6e}\t{row[7]:.6e}\t0\n')
print(f'{len(out)} rows')
