#!/usr/bin/env python3
"""Per-run flop activities for the interim (uncalibrated) core-switching estimate (Oct 29).
For every accepted energy row: counters -> per-group toggle rate per flop bit per busy cycle, written per layout as
  activity/<layout>.act.tsv : config r benchmark busy_ticks <group>=<alpha> ...
Logic groups (units): alpha_u = model_u(counters) / busy / N_rtl_bits(u, d), with N_rtl_bits(u, d) = baseline_rtl_bits(u) x
  logic_flops(u, d) / logic_flops(u, baseline) (activity_model.json; flop_group_counts.tsv). Clamped to [0, 1].
Storage: st_gpr alpha = wb_data_flips / busy / N_gpr (written-word bit changes spread over the register file);
  st_tag_<cache> alpha = 0.5 x data_fill_writes(cache) / (busy x tag entries), entries = ways x lines per way x banks (one tag
  entry rewritten per fill, half its bits change).
Usage: core_dyn_prep.py <results_root> ...  (reads ../energy_map.tsv)"""
import sys, os, re, json, glob, gzip, collections
H = os.path.dirname(os.path.abspath(__file__)); A = os.path.dirname(H)
M = json.load(open(os.path.join(H, 'activity_model.json'))); MODEL, BITS = M['model'], M['baseline_rtl_net_bits']
CNT = {}
for l in open(os.path.join(H, 'flop_group_counts.tsv')):
    if l.startswith(('#', 'layout')): continue
    lay, rest = l.rstrip('\n').split('\t', 1); CNT[lay] = {k: int(v) for k, v in (x.split('=') for x in rest.split('\t'))}
EMAP = {}
for l in open(os.path.join(A, 'energy_map.tsv')):
    if l.startswith('#') or not l.strip(): continue
    s, e, lay = l.rstrip('\n').split('\t')[:3]; EMAP[e] = lay
def parse(ctr):
    c = collections.Counter(); T = {}; INFO = {}
    for l in gzip.open(ctr, 'rt'):
        p = l.split()
        if not p: continue
        if p[0] == 'T': T[p[1]] = int(p[2])
        elif p[0] == 'C' and p[1] == 'F':
            pre = 'icache.' if '.icache.' in p[2] else ('dcache.' if '.dcache.' in p[2] else '')
            c[pre + p[3]] += int(p[4])
        elif p[0] == 'I': INFO[p[1]] = dict(x.split('=', 1) for x in p[2:])
    c['busy'] = T.get('busy_ticks', 0)
    c['dram_rd'] = sum(v for k, v in T.items() if k.startswith('mem_rd_reqs_bank'))
    c['dram_wr'] = sum(v for k, v in T.items() if k.startswith('mem_wr_reqs_bank'))
    c['dram_wr_bytes'] = sum(v for k, v in T.items() if k.startswith('mem_wr_bytes_bank'))
    return c, INFO
def activities(c, INFO, lay, busy):
    """Per-group flop activity per busy cycle from counter totals c over busy cycles (whole run here; a calibration window in
    calib/calib_window_act.py, which calls this same function)."""
    n = CNT[lay]; base = CNT['baseline']; a = {}
    for u, m in MODEL.items():
        if n.get(u, 0) == 0 or base.get(u, 0) == 0: continue
        pred = sum(coef * c.get(f, 0) for f, coef in zip(m['features'], m['coef']))
        bits = BITS[u] * n[u] / base[u]
        a[u] = min(1.0, max(0.0, pred / busy / bits))
    if n.get('st_gpr'): a['st_gpr'] = min(1.0, c.get('wb_data_flips', 0) / busy / n['st_gpr'])
    for cache in ('icache', 'dcache'):
        if not n.get(f'st_tag_{cache}'): continue
        b = [v for k, v in INFO.items() if f'.{cache}.' in k and k.endswith('.bank.sim_ctrs')]
        ent = sum(int(x['cache_size']) // int(x['line_size']) // int(x['num_banks']) for x in b)   # per bank: ways x lines per way (cache_size is the whole cache), summed over banks
        a[f'st_tag_{cache}'] = min(1.0, 0.5 * c.get(f'{cache}.data_fill_writes', 0) / busy / max(ent, 1))
    return a
def main():
    out = collections.defaultdict(list); base = CNT['baseline']
    for root in sys.argv[1:]:
        for row in sorted(glob.glob(os.path.join(root, '**', '*_energy', '*_16x.txt'), recursive=True)):
            kv = dict(l.rstrip('\n').split('=', 1) for l in open(row) if '=' in l)
            lay = EMAP[kv['config']]
            if lay not in CNT: continue
            c, INFO = parse(row[:-4] + '.ctr.gz'); busy = c['busy']; a = activities(c, INFO, lay, busy)
            out[lay].append((kv['config'], kv['mem_ratio'], kv['benchmark'], busy, a))
    os.makedirs(os.path.join(H, 'act'), exist_ok=True)
    for lay, rows in out.items():
        with open(os.path.join(H, 'act', f'{lay}.act.tsv'), 'w') as f:
            for cfg, r, b, busy, a in rows: f.write('\t'.join([cfg, r, b, str(busy)] + [f'{k}={v:.6g}' for k, v in sorted(a.items())]) + '\n')
        print(lay, len(rows))
if __name__ == '__main__': main()
