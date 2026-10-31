#!/usr/bin/env python3
"""Per-run energy for the CAL energy campaign (Oct 29 2026). One row per accepted energy run (16x).

E(run) = E_core_clock + E_core_leak + E_core_dyn + E_sram_dyn + E_sram_leak + E_dram_cmd + E_dram_io + E_dram_bg
  t_core   = busy_ticks x core period (2 ns; 16t_8w 3 ns, 8t_16w 2.5 ns: floors_vddonly.tsv 'period', checked against the row's core_period_ps)
  core     : clock (clock tree + flop clock pins) and leakage = the design's VDD-only floor (floors_vddonly.tsv) x t_core;
             dynamic = per-run core switching from core_dyn.tsv (interim uncalibrated or calibrated; empty if not yet available)
  SRAM     : sram_energy.tsv. Cache data arrays: one macro per 32-bit column, words = lines per way per bank
             (cache_size / (line_size x ways x banks)), line_size/4 macros per way; per way: reads = data_ce_cycles - data_we_cycles,
             each reading all its macros; writes = data_wr_cols x write_fixed + data_wr_bytes x write_per_byte. Local memory: one
             1024x32 macro per bank (words_per_bank from the row's I line), reads = lmem_ce - lmem_we, writes as above with lmem_we /
             lmem_wr_bytes. Flop macros (2/4/8 words): write = full-word energy per written column, plus clock energy every busy tick.
             Leakage = macros x leak x t_core.
  DRAM     : dram_inputs/dram_constants.tsv, shadow (physical-time) counts per channel: ACT x 909 pJ (includes precharge);
             transport per moved bit: shadow channel RD/RDA + WR/WRA commands x 32 B bursts (partially masked halves move a full burst), at the tier of r:
             off-chip (r = 1.0) pre-GSA + post-GSA + I/O, logic die (0.4 <= r < 1) pre + post, beside the bank (r <= 0.3) pre-GSA only;
             a design below 500 MHz uses its nominal r (r_eff x period / 2 ns: 16t_8w x 3/2, 8t_16w x 5/4). Background 34.1 mW per channel + 0.83 mW per pseudo-channel while a row is open,
             over t_dram = (dram_ticks_run + drain_ticks) x core period x r_eff, the span of the shadow's ACT counts; refresh REFab x 33.9 nJ,
             REFab (counted over the run) scaled to the same span. Rows whose drain exceeds 5% of the run are flagged (dram_lag_flag).
             (Useful bytes are kept as dram_useful_bits for reference.) e_total_J sums the parts (e_sram_flopclk_J is
             already inside e_sram_dyn_J; blank in draft mode when a part is missing). Missing core_dyn entries or counters are errors (ALLOW_MISSING_COREDYN=1 for drafts).
Usage: energy.py <results_root> [<results_root> ...]  -> ieee_cal/data/energy.csv (columns per slides/vortex26/ENERGY_CSV.md + parts)
"""
import sys, os, re, csv, glob, gzip, tarfile, math, collections
H = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(H))
def tsv(p):
    return [r for r in csv.DictReader((l for l in open(p) if not l.startswith('#')), delimiter='\t')]
EMAP = {r['energy_config']: r['layout'] for r in tsv(os.path.join(H, 'energy_map.tsv'))} if False else {}
for l in open(os.path.join(H, 'energy_map.tsv')):
    if l.startswith('#') or not l.strip(): continue
    s, e, lay = l.rstrip('\n').split('\t')[:3]; EMAP[e] = (s, lay)
FLOOR = {r['layout']: r for r in tsv(os.path.join(H, 'floors_vddonly.tsv'))}
SRAM = {r['macro']: {k: (float(v) if k not in ('macro', 'model') else v) for k, v in r.items()} for r in tsv(os.path.join(H, 'sram_energy.tsv'))}
C = {r['name']: float(r['value']) for r in tsv(os.path.join(H, 'dram_inputs/dram_constants.tsv'))}
E_ACT, E_REF = C['E_ACT'] * 1e-12, C['E_REFab_ch'] * 1e-9
P_BG, P_OPEN = C['P_PRE_SB_ch'] * 1e-3, C['dP_ACT_SB_pc'] * 1e-3
TIER = {'off': (C['e_preGSA'] + C['e_postGSA'] + C['e_IO']) * 1e-12, 'logic': (C['e_preGSA'] + C['e_postGSA']) * 1e-12, 'bank': C['e_preGSA'] * 1e-12}
# r_nom = r_eff x period / 2 ns sits within 0.6% of the 0.1 grid (row_identities.py): 16t_8w x1.5 gives 0.4005 (job ratios have 3 decimals)
def tier(r_nom): return 'off' if r_nom >= 1.0 * (1 - 0.011) else ('logic' if r_nom >= 0.4 * (1 - 0.011) else 'bank')   # 1.1%: 6000 ps rows (0.333 x 3 = 0.999)
INV = {}
for r in tsv(os.path.join(H, 'sram_inventory.tsv')): INV[r['layout']] = r['macros'] or ''
COREDYN = {}
if os.path.exists(os.path.join(H, 'core_dyn.tsv')):
    for r in tsv(os.path.join(H, 'core_dyn.tsv')): COREDYN[(r['config'], r['r'], r['benchmark'])] = (float(r['e_core_dyn_J']), int(r['calibrated']), int(r['busy_ticks']), r['layout'])

def kv(text): return dict(l.split('=', 1) for l in text.splitlines() if '=' in l)

def run(row_path):
    row = kv(open(row_path).read())
    cfg, r, bench = row['config'], row['mem_ratio'], row['benchmark']
    s_cfg, lay = EMAP[cfg]; fl = FLOOR[lay]; per = float(fl['period']) * 1e-12
    T, F, INFO = {}, collections.defaultdict(dict), {}
    for l in gzip.open(row_path[:-4] + '.ctr.gz', 'rt'):
        p = l.split()
        if not p: continue
        if p[0] == 'T': T[p[1]] = int(p[2])
        elif p[0] == 'C' and p[1] == 'F': F[p[2]][p[3]] = int(p[4])
        elif p[0] == 'I': INFO[p[1]] = dict(x.split('=', 1) for x in p[2:])
    with tarfile.open(row_path[:-4] + '.dram.tgz') as t:
        D = {os.path.basename(m.name): kv(t.extractfile(m).read().decode()) for m in t.getmembers() if m.isfile()}
    S = D['dramcmd.summary']
    assert abs(int(S['core_period_ps']) * 1e-12 - per) < 1e-15, (row_path, S['core_period_ps'], per)
    busy = T['busy_ticks']; t_core = busy * per
    o = dict(config=re.sub(r'_fpnew$', '', cfg), r=r, benchmark=bench, size=row['input_size'], layout=lay, t_core_s=t_core,
             cycles=int(row['cycles']), busy_ticks=busy)
    o['e_core_clock_J'] = (float(fl['clock_W']) + float(fl['flop_clk_internal_W'])) * t_core
    o['e_core_leak_J'] = float(fl['leakage_W']) * t_core
    cd = COREDYN.get((cfg, r, bench))
    if cd is None:
        if os.environ.get('ALLOW_MISSING_COREDYN') != '1': raise SystemExit(f'{row_path}: no core_dyn.tsv entry for {(cfg, r, bench)}')
        o['e_core_dyn_J'], o['core_dyn_calibrated'] = '', 0
    else:
        e, cal, cd_busy, cd_lay = cd
        if cd_busy != busy or cd_lay != lay: raise SystemExit(f'{row_path}: core_dyn.tsv row (busy {cd_busy}, layout {cd_lay}) != this row (busy {busy}, layout {lay})')
        o['e_core_dyn_J'], o['core_dyn_calibrated'] = e, cal
    # SRAM
    sd = sl = sclk = 0.0; nmac = collections.Counter()
    for inst, meta in INFO.items():
        if inst.endswith('.bank.sim_ctrs') and ('.icache.' in inst or '.dcache.' in inst):
            ways, line, size, banks = int(meta['num_ways']), int(meta['line_size']), int(meta['cache_size']), int(meta['num_banks'])
            words = size // (line * ways * banks); per_way = line // 4; mac = f'{words}x32'; m = SRAM[mac]
            bankpfx = inst[:-len('.sim_ctrs')]
            for w in range(ways):
                ck = f'{bankpfx}.cache_data.g_data_store[{w}].sim_ctrs'
                if ck not in F: raise SystemExit(f'{row_path}: no counters for {ck}')
                c = F[ck]
                rd = c.get('data_ce_cycles', 0) - c.get('data_we_cycles', 0)
                sd += rd * per_way * m['read_pJ'] * 1e-12
                if m['model'] == 'flop': sd += c.get('data_wr_cols', 0) * m['write_pJ'] * 1e-12
                else: sd += (c.get('data_wr_cols', 0) * m['write_fixed_pJ'] + c.get('data_wr_bytes', 0) * m['write_per_byte_pJ']) * 1e-12
                nmac[mac] += per_way
        elif '.local_mem.g_data_store[' in inst and inst.endswith('.sim_ctrs'):
            nm = int(meta.get('macros', 1)); words = int(meta['words_per_bank']) // nm; mac = f'{words}x32'; m = SRAM[mac]
            if inst not in F: raise SystemExit(f'{row_path}: no counters for {inst}')
            c = F[inst]
            sd += (c.get('lmem_ce', 0) - c.get('lmem_we', 0)) * m['read_pJ'] * 1e-12
            sd += (c.get('lmem_we', 0) * m['write_fixed_pJ'] + c.get('lmem_wr_bytes', 0) * m['write_per_byte_pJ']) * 1e-12
            nmac[mac] += nm
    for mac, n in nmac.items():
        sl += n * SRAM[mac]['leak_uW'] * 1e-6 * t_core; sclk += n * SRAM[mac]['clk_pJ_per_cycle'] * 1e-12 * busy
    o['e_sram_dyn_J'] = sd + sclk; o['e_sram_flopclk_J'] = sclk; o['e_sram_leak_J'] = sl
    o['sram_macros'] = ' '.join(f'{k}:{v}' for k, v in sorted(nmac.items()))
    # the macros derived from the row's geometry must be exactly the routed layout's SRAM instances
    inv = ' '.join(sorted(INV[lay].split())) if lay in INV else None
    if inv is None: raise SystemExit(f'{row_path}: layout {lay} not in sram_inventory.tsv')
    if ' '.join(sorted(o['sram_macros'].split())) != inv: raise SystemExit(f'{row_path}: derived SRAM [{o["sram_macros"]}] != layout {lay} [{INV[lay]}]')
    # DRAM
    r_eff = float(S['r_eff']); r_nom = r_eff * per / 2e-9   # nominal r of the 500 MHz grid: 16t_8w (3 ns) x 3/2, 8t_16w (2.5 ns) x 5/4
    # one time span for every DRAM part: the shadow's ACT counts include the drain after the run (the physical-time model
    # finishing its backlog), so background, open-row and refresh power are charged over run + drain too (audit Oct 31)
    run_t, drain_t = int(S['dram_ticks_run']), int(S['drain_ticks'])
    t_dram = (run_t + drain_t) * per * r_eff
    acts = refs = 0; openW = 0.0; chans = sorted(k for k in D if re.match(r'dramcmd\.shadow\.ch\d+$', k))
    for ch in chans:
        d = D[ch]; acts += int(d['ACT'])
        if int(d['ticks']) != run_t + drain_t or int(d['ticks_run']) != run_t: raise SystemExit(f'{row_path}: {ch} ticks {d["ticks"]}/{d["ticks_run"]} != run {run_t} + drain {drain_t}')
        refs += int(d['REFab']) * (run_t + drain_t) / run_t     # REFab is counted over the run; refresh continues at the same rate in the drain
        for pc in ('pc0', 'pc1'): openW += P_OPEN * int(d[f'{pc}.open_ticks']) * per * r_eff
    # transport = what the DRAM moves (user, Oct 31): the shadow channels' RD/RDA and WR/WRA commands x 32 B (one HBM2 pseudo-channel
    # burst each; a 64 B line read is 2 bursts, a write moves a full burst for every 32 B half with any byte enabled). Reads the
    # controller answers from its write buffer issue no command and are not charged. Useful bytes undercounted cached designs
    # 1.0-8x (p50 2.2x over cached designs). Checks: accepted read transactions = 2 x line requests; write commands = accepted write transactions.
    rd_cmd = sum(int(D[ch][k]) for ch in chans for k in ('RD', 'RDA')); wr_cmd = sum(int(D[ch][k]) for ch in chans for k in ('WR', 'WRA'))
    rd_reqs = sum(v for k, v in T.items() if k.startswith('mem_rd_reqs_bank'))
    if int(S['shadow_tx_rd']) != 2 * rd_reqs: raise SystemExit(f'{row_path}: shadow_tx_rd {S["shadow_tx_rd"]} != 2 x mem_rd_reqs {rd_reqs}')
    if wr_cmd != int(S['shadow_tx_wr']) or rd_cmd > int(S['shadow_tx_rd']): raise SystemExit(f'{row_path}: shadow commands rd {rd_cmd} wr {wr_cmd} vs transactions {S["shadow_tx_rd"]} / {S["shadow_tx_wr"]}')
    rd_b, wr_b = rd_cmd * 32 * 8, wr_cmd * 32 * 8
    o['dram_tier'] = tier(r_nom)
    o['r_nominal'] = f'{round(r_nom, 1):.1f}'   # the 500 MHz grid ratio this run stands for (job ratio x period / 2 ns), for figures
    o['e_dram_cmd_J'] = acts * E_ACT
    o['e_dram_io_J'] = (rd_b + wr_b) * TIER[tier(r_nom)]
    o['dram_io_bits'] = rd_b + wr_b
    o['dram_useful_bits'] = rd_reqs * 64 * 8 + sum(v for k, v in T.items() if k.startswith('mem_wr_bytes_bank')) * 8   # for reference: bytes the software asked for
    o['e_dram_bg_J'] = P_BG * len(chans) * t_dram + openW + refs * E_REF
    o['t_dram_s'] = t_dram; o['dram_channels'] = len(chans)
    o['dram_shadow_lag_frac'] = drain_t / run_t; o['dram_lag_flag'] = int(drain_t / run_t > 0.05)   # GATE_TABLE: flag lag above 5%
    parts = [o[k] for k in ('e_core_clock_J', 'e_core_leak_J', 'e_core_dyn_J', 'e_sram_dyn_J', 'e_sram_leak_J', 'e_dram_cmd_J', 'e_dram_io_J', 'e_dram_bg_J')]
    o['e_total_J'] = '' if '' in parts else sum(parts)   # blank (not partial) when a draft row lacks core_dyn   # e_sram_flopclk_J is inside e_sram_dyn_J
    return o

def main():
    rows = []
    for root in sys.argv[1:]:
        rows += glob.glob(os.path.join(root, '**', '*_energy', '*_16x.txt'), recursive=True)
    out = []; seen = {}
    for p in sorted(rows):
        o = run(p); k = (o['config'], o['r'], o['benchmark'])
        if k in seen: raise SystemExit(f'duplicate row {k}: {seen[k]} and {p}')
        seen[k] = p; o['source'] = os.path.abspath(p); out.append(o)
    cols = list(out[0])
    dst = os.environ.get('ENERGY_OUT', os.path.join(ROOT, 'ieee_cal', 'data', 'energy.csv'))
    with open(dst, 'w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=cols); w.writeheader(); w.writerows(out)
    print(f'{len(out)} rows -> {dst}')
if __name__ == '__main__': main()
