#!/usr/bin/env python3
"""Netlist identity check for sv2v output that is independent of file order.
sv2v numbers genvars (_gv_*_N) and hashes generated names (5 hex digits) in processing order, and module order follows the
gen_sources file order, so byte md5 is not reproducible across build dirs. This compares, per module, the multiset of
lines with those generated names normalized, plus the lines outside modules. Exit 0 = identical."""
import sys, re
from collections import Counter
def norm(l):
    l = re.sub(r'_gv_(\w+?)_\d+\b', r'_gv_\1_N', l)
    return re.sub(r'(?<=_)[0-9A-F]{5}(?=_|\b)', 'H', l).strip()
def parse(f):
    d, cur, out = {}, None, Counter()
    for l in open(f):
        m = re.match(r'\s*module\s+(\w+)', l)
        if m and cur is None: cur = norm(m.group(1)); d.setdefault(cur, Counter()); d[cur]["#instances"] += 1
        if cur: d[cur][norm(l)] += 1
        else: out[norm(l)] += 1
        if cur and re.match(r'\s*endmodule', l): cur = None
    return d, out
(A, oa), (B, ob) = parse(sys.argv[1]), parse(sys.argv[2])
diff = sorted(k for k in set(A) | set(B) if A.get(k) != B.get(k))
ok = not diff and oa == ob
print(('IDENTICAL' if ok else 'DIFFERENT'), 'modules', len(A), len(B), 'differ', diff[:6], 'outside_same', oa == ob)
sys.exit(0 if ok else 1)
