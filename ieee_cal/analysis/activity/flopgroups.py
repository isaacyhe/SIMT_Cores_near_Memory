#!/usr/bin/env python3
"""Classify every flip-flop of a routed netlist (6_final.v) into an activity group (Oct 29, interim core-switching estimate).
Groups: '<unit>' for logic flops (units = the activity model's units, analyze.py regexes, first match wins), and storage families
whose bits change only on writes: st_gpr (operand-collector register file), st_tag_icache / st_tag_dcache (cache tag stores);
other storage (MSHR, instruction buffer, memory queues, IPDOM stack, ...) stays in its unit's logic group (interim choice).
Usage: flopgroups.py <6_final.v> <out_groups.tsv>   -> lines 'group<TAB>instance'; prints the group counts."""
import sys, re, collections
UNITS = [('sim_only', r'sim_ctrs|sim_tgl|sim_cyc|perf'), ('icache', r'^icache'), ('dcache', r'^dcache'), ('fetch', r'core\.fetch'),
 ('decode', r'core\.decode'), ('sched', r'core\.schedule'), ('gpr_opc', r'core\.issue\..*operands'), ('issue', r'core\.issue'),
 ('imul_idiv', r'core\.execute\.alu_unit\..*muldiv'), ('alu', r'core\.execute\.alu_unit'), ('fpu', r'core\.execute\.fpu_unit'),
 ('sfu', r'core\.execute\.sfu_unit'), ('lmem', r'core\.mem_unit\..*local_mem'), ('lsu', r'core\.mem_unit'), ('commit', r'core\.commit'),
 ('core_other', r'g_cores\[0\]'), ('mem_ic', r'.')]
URE = [(u, re.compile(p)) for u, p in UNITS]
STORE = [('st_gpr', re.compile(r'opc_unit\.g_gpr_ram')), ('st_tag_icache', re.compile(r'^icache\..*cache_tags\.g_tag_store')),
         ('st_tag_dcache', re.compile(r'^dcache\..*cache_tags\.g_tag_store'))]
PFX = 'g_clusters[0].cluster.g_sockets[0].socket.'
CELL = re.compile(r'^\s*((?:ASYNC_)?DFF\w*|DHLx\w*|DLLx\w*|SDF\w*)\s+(\S+)\s*\(')
def group(inst):
    if not inst.startswith(PFX): return '_anonymous'
    r = inst[len(PFX):]
    for g, rx in STORE:
        if rx.search(r): return g
    return next(u for u, rx in URE if rx.search(r))
if __name__ == '__main__':
    cnt = collections.Counter()
    with open(sys.argv[2], 'w') as out:
        for line in open(sys.argv[1]):
            m = CELL.match(line)
            if not m: continue
            inst = m.group(2).lstrip('\\'); g = group(inst); cnt[g] += 1
            out.write(f'{g}\t{inst}\n')
    print('\t'.join(f'{k}={v}' for k, v in sorted(cnt.items())))
