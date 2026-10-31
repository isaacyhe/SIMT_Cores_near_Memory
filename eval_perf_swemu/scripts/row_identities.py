#!/usr/bin/env python3
"""CAL energy row content check (used by row_accept.sh; not part of the build id).
Usage: row_identities.py <result.txt> <result.ctr.gz> <result.dram.tgz>
Prints one line per violated identity (nothing = consistent). Checks that the counter file and the DRAM files are complete and
internally consistent, and that the row's own DRAM fields equal the raw channel files (based on the fifth sim audit's dramchk)."""
import sys, gzip, math, tarfile, io, collections, re

class _Stop(Exception):
    pass

# ---- presence: every counter group the row's own build must have, with its geometry (absent != 0 silently).
# Expectations follow VX_config.vh for the flags the wave configs use (one core, ISSUE_WIDTH 1, one LSU block):
# caches 1 bank, ways/size from the flags (default 4 ways, 16 KB); dcache word = 4 x threads; local memory
# NUM_THREADS banks of 16 KB total (LMEM_LOG_SIZE 14); FPU lanes = NUM_THREADS, one T-Head divsqrt per lane;
# operand collectors = ceil(warps / 4); split/join only with more than one thread.
CTRS = {'way': 6, 'cbank': 11, 'lmem': 11, 'divsqrt': 3, 'fpu': 6, 'alu': 5, 'muldiv': 3, 'fetch': 1, 'schedule': 4,
        'issue': 11, 'opc': 4, 'commit': 2, 'mem_unit': 5, 'split_join': 2,
        'tgl_issue': 1, 'tgl_opc': 1, 'tgl_cbank': 3, 'tgl_lmem': 3, 'tgl_mem_unit': 3, 'tgl_muldiv': 2, 'tgl_sj': 2, 'tgl_lpath': 3,
        'cyc_issue': 1, 'cyc_opc': 1, 'cyc_cbank': 3, 'cyc_lmem': 3, 'cyc_mem_unit': 3, 'cyc_lpath': 3, 'cyc_muldiv': 1, 'cyc_sj': 2,
        'cyc_disp_alu': 1, 'cyc_disp_fpu': 1, 'cyc_disp_lsu': 1, 'cyc_disp_sfu': 1,
        'cyc_way': 3, 'cyc_byp': 4, 'cyc_byp_l2': 4, 'cyc_byp_l3': 4}   # Oct 27: data-array ports, cache bypass buses   # sim_cyc: every-cycle bus changes     # sim_tgl: data-bus bit flips per transfer (Oct 26)
def classify(inst):
    if inst.endswith('.core.mem_unit.g_sim_ctrs[0].sim_cyc_lmem'): return 'cyc_lpath'
    if inst.endswith('.cache_bypass.sim_cyc'):
        if '.l3cache.' in inst: return 'cyc_byp_l3'
        if '.l2cache.' in inst: return 'cyc_byp_l2'
        if '.icache.' in inst or '.dcache.' in inst: return ('icache' if '.icache.' in inst else 'dcache') + '_cyc_byp'
        return None
    if inst.endswith('.sim_cyc') and '.cache_data.g_data_store[' in inst: return ('icache' if '.icache.' in inst else 'dcache') + '_cyc_way'
    if inst.endswith('.sim_cyc'):
        if '.local_mem.g_data_store[' in inst: return 'cyc_lmem'
        if inst.endswith('.bank.sim_cyc') and '.g_banks[' in inst: return ('icache' if '.icache.' in inst else 'dcache') + '_cyc_cbank'
        if inst.endswith('.issue_slice.sim_cyc'): return 'cyc_issue'
        if inst.endswith('.opc_unit.sim_cyc'): return 'cyc_opc'
        if inst.endswith('.core.mem_unit.g_sim_ctrs[0].sim_cyc'): return 'cyc_mem_unit'
        if inst.endswith('.muldiv_unit.sim_cyc'): return 'cyc_muldiv'
        if inst.endswith('.split_join.g_enable.sim_cyc'): return 'cyc_sj'
        for u in ('alu', 'fpu', 'lsu', 'sfu'):   # one per issue slice (g_sim_cyc[0 .. ISSUE_WIDTH-1])
            if re.search(rf'\.{u}_unit\.g_sim_cyc\[\d+\]\.sim_cyc$', inst): return f'cyc_disp_{u}'
        return None
    if inst.endswith('.core.mem_unit.g_sim_ctrs[0].sim_tgl_lmem'): return 'tgl_lpath'
    if inst.endswith('.sim_tgl'):
        if '.local_mem.g_data_store[' in inst: return 'tgl_lmem'
        if inst.endswith('.bank.sim_tgl') and '.g_banks[' in inst: return ('icache' if '.icache.' in inst else 'dcache') + '_tgl_cbank'
        if inst.endswith('.issue_slice.sim_tgl'): return 'tgl_issue'
        if inst.endswith('.opc_unit.sim_tgl'): return 'tgl_opc'
        if inst.endswith('.core.mem_unit.g_sim_ctrs[0].sim_tgl'): return 'tgl_mem_unit'
        if inst.endswith('.muldiv_unit.sim_tgl'): return 'tgl_muldiv'
        if inst.endswith('.split_join.g_enable.sim_tgl'): return 'tgl_sj'
        return None
    if '.cache_data.g_data_store[' in inst: return ('icache' if '.icache.' in inst else 'dcache') + '_way'
    if inst.endswith('.bank.sim_ctrs') and '.g_banks[' in inst: return ('icache' if '.icache.' in inst else 'dcache') + '_cbank'
    if '.local_mem.g_data_store[' in inst: return 'lmem'
    if 'i_fpnew_divsqrt_multi_th.sim_ctrs' in inst: return 'divsqrt'
    if re.search(r'\.fpu_unit\.g_blocks\[\d+\]\.sim_ctrs$', inst): return 'fpu'   # one per FPU block (= ISSUE_WIDTH)
    if inst.endswith('.muldiv_unit.sim_ctrs'): return 'muldiv'
    if re.search(r'\.alu_unit\.g_blocks\[\d+\]\.sim_ctrs$', inst): return 'alu'
    if re.search(r'\.core\.commit\.g_sim_ctrs\[\d+\]\.sim_ctrs$', inst): return 'commit'   # one per issue slice   # one per ALU block (= ISSUE_WIDTH)
    for k, suf in (('fetch', '.core.fetch.sim_ctrs'), ('schedule', '.core.schedule.sim_ctrs'), ('split_join', '.split_join.g_enable.sim_ctrs'),
                   ('issue', '.issue_slice.sim_ctrs'), ('opc', '.opc_unit.sim_ctrs'),
                   ('mem_unit', '.core.mem_unit.g_sim_ctrs[0].sim_ctrs')):
        if inst.endswith(suf): return k
    return None

def presence(row, FI, INFO, ck):
    D = {}
    for f in row.get('rtlsim_configs', '').split():
        if f.startswith('-D'):
            k, _, v = f[2:].partition('='); D[k] = v
    i = lambda k, d: int(D[k]) if D.get(k) else d
    nt, nw = i('NUM_THREADS', 4), i('NUM_WARPS', 4)
    l1off = 'L1_DISABLE' in D
    has = {'icache': not (l1off or 'ICACHE_DISABLE' in D), 'dcache': not (l1off or 'DCACHE_DISABLE' in D)}
    lmem = 'LMEM_DISABLE' not in D
    # VX_config.vh (Oct 28, wide wave-2b configs): ISSUE_WIDTH = UP(NUM_WARPS/16) issue slices, each with its own ALU/FPU block and
    # dispatch counters; dcache banks = MIN(DCACHE_NUM_REQS, 16), DCACHE_NUM_REQS = UP(NUM_LSU_LANES*4 / LSU_LINE_SIZE) with
    # LSU_LINE_SIZE = MIN(NUM_LSU_LANES*4, 64) (one LSU block); dcache word size = LSU_LINE_SIZE. The icache has one bank.
    iw = max(1, nw // 16)
    lsl = min(4 * nt, 64)
    nbank = {'icache': 1, 'dcache': min(-(-(4 * nt) // lsl), 16)}
    want = {'fetch': 1, 'schedule': 1, 'issue': iw, 'alu': iw, 'muldiv': iw, 'fpu': iw, 'commit': iw, 'mem_unit': 1,
            'opc': -(-nw // 4), 'split_join': 1 if nt > 1 else 0, 'divsqrt': 0 if 'FPU_DIVSQRT_DISABLE' in D else iw * nt, 'lmem': nt if lmem else 0,
            'tgl_issue': iw, 'tgl_opc': -(-nw // 4), 'tgl_lmem': nt if lmem else 0, 'tgl_mem_unit': 1,
            'tgl_muldiv': iw, 'tgl_sj': 1 if nt > 1 else 0, 'tgl_lpath': 1 if lmem else 0,
            'cyc_issue': iw, 'cyc_opc': -(-nw // 4), 'cyc_lmem': nt if lmem else 0, 'cyc_mem_unit': 1, 'cyc_muldiv': iw,
            'cyc_sj': 1 if nt > 1 else 0, 'cyc_lpath': 1 if lmem else 0,
            'cyc_disp_alu': iw, 'cyc_disp_fpu': iw, 'cyc_disp_lsu': iw, 'cyc_disp_sfu': iw, 'cyc_byp_l2': 1, 'cyc_byp_l3': 1,
            'dcache_cyc_byp': 1, 'icache_cyc_byp': 0 if has['icache'] else 1}
    for c in ('icache', 'dcache'):
        nb = nbank[c] if has[c] else 0
        want[c + '_cbank'] = nb
        want[c + '_cyc_cbank'] = nb
        want[c + '_cyc_way'] = i(c.upper() + '_NUM_WAYS', 4) * nb
        want[c + '_way'] = i(c.upper() + '_NUM_WAYS', 4) * nb
        want[c + '_tgl_cbank'] = nb
    got = collections.Counter(); unknown = []
    for inst, names in FI.items():
        k = classify(inst)
        if k is None: unknown.append(inst); continue
        got[k] += 1
        n = CTRS[k.split('_', 1)[1] if k.startswith(('icache_', 'dcache_')) else k]
        if k == 'muldiv' and 'IDIV_DISABLE' in D: n = 1   # Oct 28: no divider -> imul_fire only
        ck(len(names) == n, f'presence: {inst.rsplit(".", 2)[-2]} has {len(names)} counters (expected {n})')
    ck(not unknown, f'presence: unexpected counter groups {unknown[:3]}')
    for k, n in want.items():
        ck(got[k] == n, f'presence: {got[k]} {k} groups (expected {n} for this config)')
    # geometry reported by the hardware itself (I lines) matches the config
    for c in ('icache', 'dcache'):
        if not has[c]: continue
        banks = [v for k, v in INFO.items() if f'.{c}.' in k and k.endswith('.bank.sim_ctrs')]
        ways = sorted(int(v['way']) for k, v in INFO.items() if f'.{c}.' in k and '.cache_data.g_data_store[' in k)
        nways, size = i(c.upper() + '_NUM_WAYS', 4), i(c.upper() + '_SIZE', 16384)
        nb = nbank[c]
        ck(len(banks) == nb and all(b.get('num_banks') == str(nb) and b.get('num_ways') == str(nways) and b.get('cache_size') == str(size) for b in banks),
           f'presence: {c} geometry {banks} != {nb} banks, ways {nways}, size {size}')
        ck(ways == sorted(list(range(nways)) * nb), f'presence: {c} way info {ways}')
        wsz = {v.get('word_size') for k, v in INFO.items() if f'.{c}.' in k and '.cache_data.g_data_store[' in k}
        ck(wsz == {str(lsl if c == 'dcache' else 4)}, f'presence: {c} word size {wsz}')
    lb = [v for k, v in INFO.items() if '.local_mem.g_data_store[' in k]
    if lmem:
        ck(sorted(int(v['bank']) for v in lb) == list(range(nt)) and all(int(v['words_per_bank']) * nt == 4096 for v in lb),
           f'presence: local memory info {lb[:2]} for {nt} threads')
    else:
        ck(not lb, 'presence: local memory info present with LMEM_DISABLE')
    fl = [v.get('num_lanes') for k, v in INFO.items() if re.search(r'\.fpu_unit\.g_blocks\[\d+\]\.sim_ctrs$', k)]
    ck(fl == [str(nt)] * iw, f'presence: FPU lanes {fl} (expected {iw} x {nt})')
    # operand-collector register banks: 4 banks of (64 regs x warps / 4 / collectors) entries, 32 bits per thread
    # (this separates warp counts the instance counts alone cannot: 2 vs 4 warps, 8 vs 16)
    nopc = -(-nw // 4)
    oi = [v for k, v in INFO.items() if k.endswith('.opc_unit.sim_ctrs')]
    ck(len(oi) == nopc and all(v.get('num_banks') == '4' and v.get('bank_size') == str(64 * nw // 4 // nopc) and v.get('bank_data_width') == str(32 * nt)
                               for v in oi), f'presence: operand collector info {oi[:1]} != 4 banks x {64 * nw // 4 // nopc} x {32 * nt} bits')

bad = []
def main():
    global bad
    row_f, ctr_f, dram_f = sys.argv[1:4]
    def ck(cond, msg):
        if not cond: bad.append(msg)

    row = {}
    for l in open(row_f):
        l = l.rstrip('\n')
        if '=' in l:
            k, v = l.split('=', 1)
            row.setdefault(k, v)

    # ---- DRAM files: exactly the 7 expected members
    EXPECT = {'dramcmd.summary', 'dramcmd.timing.ch0', 'dramcmd.timing.ch1', 'dramcmd.shadow.ch0', 'dramcmd.shadow.ch1',
              'dramcmd.timing.stats', 'dramcmd.shadow.stats'}
    files = {}
    try:
        with tarfile.open(dram_f) as t:
            for m in t.getmembers():
                if m.isfile():
                    files[m.name] = t.extractfile(m).read().decode(errors='replace')
    except Exception as e:
        bad.append(f'dram tgz unreadable: {e}'); raise _Stop()
    ck(set(files) == EXPECT, f'dram tgz members {sorted(files)}')
    if not EXPECT <= set(files):
        raise _Stop()
    kv = lambda txt: dict(l.strip().split('=', 1) for l in txt.splitlines() if '=' in l)
    summ = kv(files['dramcmd.summary'])
    ck(files['dramcmd.summary'].rstrip().endswith('END'), 'summary lacks END')
    try:
        I = int
        tr, dr = I(summ['dram_ticks_run']), I(summ['drain_ticks'])
        refi, nrfc = float(summ['shadow_refi_ticks']), I(summ['shadow_nrfc'])
        # Oct 27 (audit 20): the summary prints refi with 6 significant digits; at 3000 ps it is non-integer (1949.0254873 -> 1949.03),
        # so recompute the shadow's exact values with the same IEEE steps as dram_sim.cpp (r_eff = k/1000) and check the printed ones.
        cp = int(summ.get('core_period_ps', '2000'))
        cfg_cp = ([f.split('=', 1)[1] for f in row.get('rtlsim_configs', '').split() if f.startswith('-DCORE_PERIOD_PS=')] or ['2000'])[-1]   # last -D wins, as in the compiler
        ck(str(cp) == cfg_cp, f'DRAM core_period_ps {cp} != -DCORE_PERIOD_PS {cfg_cp} in rtlsim_configs')
        tick_ns = cp / 1000.0 * (round(float(summ['r_eff']) * 1000) / 1000)
        refi_x, nrfc_x = 3900.0 / tick_ns, math.ceil(350.0 / tick_ns)
        ck(abs(refi_x - refi) <= 1e-5 * refi and nrfc_x == nrfc, f'printed refi/nRFC {refi}/{nrfc} != recomputed {refi_x}/{nrfc_x}')
        refi = refi_x
        # the scaled ratio must correspond to a nominal 500 MHz grid ratio (0.1 .. 1.0): r x period/2000 ps (16t_8w: 0.667 x 1.5 = 1.0005)
        r_nom = float(summ['r_eff']) * cp / 2000.0
        # Oct 31 (user grid): at 6000 ps (166.67 MHz) the 3-decimal job ratio 0.033 for nominal 0.1 is 1.0% short (the sim resolves r to
        # 0.001); that period alone gets 1.1%, every other period keeps 0.6% (16t_8w at 3000 ps: +0.5%)
        tol = 0.011 if cp == 6000 else 0.006
        ck(any(abs(r_nom - g / 10) <= tol * g / 10 for g in range(1, 11)), f'mem_ratio x period/2000 = {r_nom:.4f} is not a nominal grid ratio (0.1 .. 1.0)')
        def shadow_refs(tr, refi):   # VxPhysRefresh: m_next starts at refi, fires when double(m_clk) >= m_next, then m_next += refi
            n, nxt = 0, refi
            while nxt <= tr: n += 1; nxt += refi
            return n
        lr, lw = I(summ['lines_rd']), I(summ['lines_wr'])
        ck(summ.get('drained') == '1', 'not drained'); ck(summ.get('shadow_mode') == 'physical', 'shadow not physical')
        ck(I(summ['timing_sub_rd']) == 4 * lr, 'timing_sub_rd != 4 x lines_rd'); ck(I(summ['timing_sub_wr']) == 4 * lw, 'timing_sub_wr != 4 x lines_wr')
        ck(I(summ['shadow_tx_rd']) == 2 * lr, 'shadow_tx_rd != 2 x lines_rd')
        ck(I(summ['shadow_tx_wr']) == 2 * lw - I(summ['shadow_tx_masked']), 'shadow_tx_wr != 2 x lines_wr - masked')
        for inst in ('timing', 'shadow'):
            tot = collections.Counter()
            for ch in (0, 1):
                c = kv(files[f'dramcmd.{inst}.ch{ch}'])
                for k, v in c.items():
                    if v != 'NA': tot[k] += int(v)
                tag = f'{inst} ch{ch}'
                ck(I(c['ticks_run']) == tr, f'{tag} ticks_run {c["ticks_run"]} != dram_ticks_run {tr}')
                ck(I(c['ticks']) == tr + dr, f'{tag} ticks != run + drain')
                ck(I(c['open_ticks_run']) <= I(c['ticks_run']), f'{tag} open_ticks_run > ticks_run')
                ck(0 <= I(c['open_ticks']) - I(c['open_ticks_run']) <= dr, f'{tag} drain part of open_ticks out of range')
                pcs = [I(c[k]) for k in c if k.startswith('pc') and k.endswith('.open_ticks_run')]
                ck(len(pcs) <= 2 and all(p <= I(c['open_ticks_run']) for p in pcs) and sum(pcs) >= I(c['open_ticks_run']), f'{tag} pc open bounds')
                for k in ('ACT', 'PRE', 'RD', 'WR'):
                    ck(I(c[k]) == sum(I(c.get(f'pc{p}.{k}', 0)) for p in (0, 1)), f'{tag} {k} != pc0 + pc1')
                if inst == 'shadow':
                    ck(I(c['REFab']) == shadow_refs(tr, refi), f'{tag} REFab {c["REFab"]} != replayed refresh count {shadow_refs(tr, refi)}')
                    ck(c['REF_to_ACT_min'] == 'NA' or I(c['REF_to_ACT_min']) >= nrfc, f'{tag} REF->ACT < nRFC')
                    ck(I(c['PREA']) <= I(c['REFab']), f'{tag} PREA > REFab')
                else:
                    ck(I(c['REFab']) == 0 and I(c['PREA']) == 0, f'{tag} timing model issued refresh')
                ck(I(c['ACT_reopen_PREA']) <= I(c['ACT_after_PREA']) <= I(c['PREA_banks_closed']), f'{tag} PREA reopen chain')
                open_end = I(c['ACT']) - I(c['PRE']) - I(c['PREA_banks_closed']) - I(c['RDA']) - I(c['WRA'])
                ck(0 <= open_end <= 32, f'{tag} banks open at end {open_end}')
            sub_rd = I(summ['timing_sub_rd'] if inst == 'timing' else summ['shadow_tx_rd'])
            sub_wr = I(summ['timing_sub_wr'] if inst == 'timing' else summ['shadow_tx_wr'])
            ck(tot['WR'] == sub_wr, f'{inst} WR {tot["WR"]} != accepted {sub_wr}'); ck(tot['RD'] <= sub_rd, f'{inst} RD > accepted')
            # every field run_single derives from the channel files: counts summed, *ticks* as _sum and _max, REF_to_ACT_min as the min
            chs = [kv(files[f'dramcmd.{inst}.ch{ch}']) for ch in (0, 1)]
            for k in sorted(set(chs[0]) | set(chs[1])):
                vals = [c[k] for c in chs if k in c]
                if k == 'REF_to_ACT_min':
                    nums = [int(v) for v in vals if v != 'NA']
                    want = {f'dram_{inst}_{k}': str(min(nums)) if nums else 'NA'}
                elif 'ticks' in k:
                    want = {f'dram_{inst}_{k}_sum': str(sum(int(v) for v in vals)), f'dram_{inst}_{k}_max': str(max(int(v) for v in vals))}
                else:
                    want = {f'dram_{inst}_{k}': str(sum(int(v) for v in vals))}
                for rk, rv in want.items():
                    ck(row.get(rk) == rv, f'row {rk}={row.get(rk)} != raw files {rv}')
            ck(row.get(f'dram_{inst}_ticks_run_max') == str(tr), f'row dram_{inst}_ticks_run_max != {tr}')
        for k, v in summ.items():
            ck(row.get(f'dram_sum_{k}') == v, f'row dram_sum_{k} != summary')
        ck(row.get('dram_shadow_lag_frac') == f'{(dr / tr if tr > 0 else 0):.6f}', 'row dram_shadow_lag_frac != summary')
        ck(row.get('dram_shadow_backlog_mean') == f'{(int(summ["shadow_backlog_sum"]) / tr if tr > 0 else 0):.3f}', 'row dram_shadow_backlog_mean != summary')
    except (KeyError, ValueError) as e:
        bad.append(f'dram field missing or malformed: {e}')

    # ---- counter file: one header, ends with END, identities
    E = {}; C = collections.defaultdict(collections.Counter); T = {}; heads = 0; last = ''
    FI = collections.defaultdict(set); INFO = {}; CS = collections.defaultdict(set)
    try:
        for l in gzip.open(ctr_f, 'rt'):
            last = l.strip()
            q = l.split()
            if not q: continue
            if q[0] == 'H': heads += 1
            elif q[0] == 'E': E[q[1]] = q[2]
            elif q[0] == 'C':
                ck((q[2], q[3]) not in CS[q[1]], f'duplicate counter line {q[1]} {q[2].rsplit(".", 2)[-2]} {q[3]}')
                C[q[1]][q[3]] += int(q[4])
                CS[q[1]].add((q[2], q[3]))
                if q[1] == 'F': FI[q[2]].add(q[3])
            elif q[0] == 'I':
                ck(q[1] not in INFO, f'duplicate info line {q[1].rsplit(".", 2)[-2]}'); INFO[q[1]] = dict(x.split('=', 1) for x in q[2:] if '=' in x)
            elif q[0] == 'T':
                ck(q[1] not in T, f'duplicate host total {q[1]}'); T[q[1]] = int(q[2])
    except Exception as e:
        bad.append(f'ctr file unreadable: {e}'); raise _Stop()
    ck(heads == 1, f'ctr headers {heads}'); ck(last == 'END', 'ctr file does not end with END')
    F = C.get('F', collections.Counter())
    ck(len(F) > 0, 'ctr file has no final dump')
    if F:
        g = lambda n: F.get(n, 0)
        ck(g('issue_any') == g('commit_warp_instrs'), 'issue != commit warp instrs')
        ck(g('issue_alu') == g('alu_arith') + g('alu_branch') + g('alu_muldiv') + g('alu_other'), 'ALU issue != ALU types')
        ck(g('alu_muldiv') == g('imul_fire') + g('idiv_fire'), 'muldiv != imul + idiv')
        # soft-math configs (Oct 28): the removed units never fire (the RTL guards would also have stopped the run)
        DF = {f[2:].partition('=')[0] for f in row.get('rtlsim_configs', '').split() if f.startswith('-D')}
        if 'IDIV_DISABLE' in DF:
            ck('idiv_fire' not in F and g('div_opd_flips') == 0, 'IDIV_DISABLE: divider counters present or non-zero')
        if 'FPU_DIVSQRT_DISABLE' in DF:
            ck(g('fpu_div') == 0 and g('fpu_sqrt') == 0, 'FPU_DIVSQRT_DISABLE: FDIV/FSQRT issued')
        ck(g('issue_fpu') == g('fpu_any') == g('fpu_fma') + g('fpu_div') + g('fpu_sqrt') + g('fpu_cvt') + g('fpu_ncp'), 'FPU issue/classes')
        ck(g('fill_st0') == g('miss_primary') == g('mem_rsp_fire'), 'cache fills != primary misses != mem responses')
        ck(g('data_we_cycles') == g('data_fill_writes') + g('data_write_hits'), 'data we != fills + write hits')
        # data-bus bit flips (sim_tgl) are bounded by bus width x transfers (cache lines are 512 bits; dcache/icache summed by name)
        nt_ = int(dict(f[2:].partition('=')[::2] for f in row.get('rtlsim_configs', '').split() if f.startswith('-D')).get('NUM_THREADS') or 4)
        ck(0 <= g('opd_data_flips') <= 3 * 32 * nt_ * g('issue_any'), 'operand-bus flips out of bounds')
        ck(0 <= g('wb_data_flips') <= 32 * nt_ * g('gpr_writes'), 'writeback flips out of bounds')
        ck(0 <= g('st0_data_flips') <= 512 * (g('fill_st0') + g('wr_st0') + g('wr_st0_replay')), 'cache st0 data flips out of bounds')
        ck(0 <= g('read_data_flips') <= 512 * (g('rd_st0') + g('rd_st0_replay')), 'cache read data flips out of bounds')
        ck(0 <= g('lmem_wdata_flips') <= 32 * g('lmem_we') and 0 <= g('lmem_rdata_flips') <= 32 * g('lmem_ce'), 'local-memory flips out of bounds')
        ck(0 <= g('lmem_addr_flips') <= 32 * g('lmem_ce'), 'local-memory address flips out of bounds')
        ck(0 <= g('st0_addr_flips') <= 32 * (g('rd_st0') + g('rd_st0_replay') + g('wr_st0') + g('wr_st0_replay') + g('fill_st0') + 2 * T.get('busy_ticks', 0)), 'cache st0 address flips out of bounds')
        ck(0 <= g('lsu_addr_flips') <= 32 * nt_ * (g('lsu_req_rd') + g('lsu_req_wr')), 'LSU address flips out of bounds')
        ck(0 <= g('lsu_wdata_flips') <= 32 * nt_ * g('lsu_req_wr'), 'LSU store-data flips out of bounds')
        ck(0 <= g('lsu_rdata_flips') <= 32 * nt_ * T.get('busy_ticks', 0), 'LSU load-data flips out of bounds')
        ck(0 <= g('mul_opd_flips') <= 64 * nt_ * g('imul_fire') and 0 <= g('div_opd_flips') <= 64 * nt_ * g('idiv_fire'), 'multiply/divide operand flips out of bounds')
        ck(0 <= g('ipdom_push_flips') <= 2 * (nt_ + 32) * g('ipdom_push') and 0 <= g('ipdom_pop_flips') <= (nt_ + 32) * g('ipdom_pop'), 'IPDOM stack flips out of bounds')
        ck(0 <= g('lpath_addr_flips') <= 32 * nt_ * (g('lsu_req_rd') + g('lsu_req_wr')) and 0 <= g('lpath_wdata_flips') <= 32 * nt_ * g('lsu_req_wr')
           and 0 <= g('lpath_rdata_flips') <= 32 * nt_ * T.get('busy_ticks', 0), 'local-memory path flips out of bounds')
        # every-cycle bus changes: at most the bus width per counting cycle (core_ticks) per instance
        ct = T.get('core_ticks', 0); nw_ = -(-int(dict(f[2:].partition('=')[::2] for f in row.get('rtlsim_configs', '').split() if f.startswith('-D')).get('NUM_WARPS') or 4) // 4)
        for n, wbits in (('opd_data_cyc', 96 * nt_), ('wb_data_cyc', 32 * nt_ * nw_), ('st0_data_cyc', 2 * 512), ('read_data_cyc', 2 * 512), ('st0_addr_cyc', 2 * 32),
                         ('lmem_wdata_cyc', 32 * nt_), ('lmem_rdata_cyc', 32 * nt_), ('lmem_addr_cyc', 32 * nt_), ('lsu_addr_cyc', 32 * nt_), ('lsu_wdata_cyc', 32 * nt_),
                         ('lsu_rdata_cyc', 32 * nt_), ('lpath_addr_cyc', 32 * nt_), ('lpath_wdata_cyc', 32 * nt_), ('lpath_rdata_cyc', 32 * nt_), ('mdu_opd_cyc', 64 * nt_),
                         ('ipdom_d_cyc', 2 * (nt_ + 32)), ('ipdom_q_cyc', nt_ + 32),
                         ('alu_disp_cyc', 96 * nt_ + 256), ('fpu_disp_cyc', 96 * nt_ + 256), ('lsu_disp_cyc', 96 * nt_ + 256), ('sfu_disp_cyc', 96 * nt_ + 256),
                         ('dway_wdata_cyc', 2 * 8 * 512), ('dway_rdata_cyc', 2 * 8 * 512), ('dway_wren_cyc', 2 * 8 * 64),
                         ('byp_creq_cyc', 4 * 8192), ('byp_crsp_cyc', 4 * 8192), ('byp_mreq_cyc', 4 * 8192), ('byp_mrsp_cyc', 4 * 8192)):
            ck(0 <= g(n) <= wbits * ct, f'{n} out of bounds')
        for ep in E:
            ck(CS.get(ep, set()) == CS['F'], f'snapshot {E[ep]} has {len(CS.get(ep, set()))} (instance, counter) lines, final dump {len(CS["F"])}')
        pl1 = [k for k, t in E.items() if t == 'pre_launch_1']
        ck(bool(pl1) and all(v == 0 for v in C[pl1[0]].values()), 'counters non-zero at pre_launch_1')
        nl = sum(1 for t in E.values() if t.startswith('pre_launch_'))
        ck(nl == T.get('launches', -1), 'pre_launch snapshots != launches')
        try:
            tail = g('commit_thread_instrs') - int(row.get('instructions', '0'))
            ck(nl > 0 and tail in (125 * nl, 126 * nl), f'commit thread instrs - instret = {tail} (expected 125/126 x {nl})')
        except ValueError:
            bad.append('instructions not an integer')
    if F:
        presence(row, FI, INFO, ck)
    try:
        r = float(summ['r_eff'])
        ck(sum(v for k, v in T.items() if k.startswith('mem_rd_reqs_bank')) == int(summ['lines_rd']), 'host DRAM reads != DramSim lines')
        ck(sum(v for k, v in T.items() if k.startswith('mem_wr_reqs_bank')) == int(summ['lines_wr']), 'host DRAM writes != DramSim lines')
        ck(abs(T['core_ticks'] - int(summ['dram_ticks_run']) * r) <= 1 + r, 'core ticks != DRAM ticks x r')
        ck(T.get('dram_queue_discards') == 0, 'DRAM queue discards')
        # the row ran at its job's memory clock ratio
        ck(abs(r - float(row.get('mem_ratio', 'nan'))) < 1e-6, f'DRAM r_eff {r} != mem_ratio {row.get("mem_ratio")}')
        # time base: busy ticks (T_core) = scheduler busy cycles; core ticks = busy + 10 + 14 per launch (reset/launch overhead)
        nlch = T.get('launches', -1)
        ck(T['busy_ticks'] == F.get('sched_busy_cycles', -1), f'busy_ticks {T["busy_ticks"]} != sched_busy_cycles {F.get("sched_busy_cycles")}')
        ck(T['core_ticks'] - T['busy_ticks'] == 10 + 14 * nlch, f'core_ticks - busy_ticks = {T["core_ticks"] - T["busy_ticks"]} (expected {10 + 14 * nlch})')
        # perf cycles (CSR, kernel window) inside the busy window: shorter by the launch/exit overhead only
        cyc = int(row.get('cycles', '0'))
        ck(0 < cyc <= T['busy_ticks'] and T['busy_ticks'] - cyc <= 10000 * max(nlch, 1), f'cycles {cyc} vs busy_ticks {T["busy_ticks"]} ({nlch} launches)')
    except (KeyError, ValueError) as e:
        bad.append(f'host totals missing: {e}')

try:
    main()
except _Stop:
    pass
except BaseException as e:          # any crash is a failure, never a silent accept
    bad.append(f'identity check crashed: {type(e).__name__}: {e}')
if bad:
    print('; '.join(bad)); sys.exit(1)
print('IDENTITIES_OK')
