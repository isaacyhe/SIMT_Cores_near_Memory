"""Collect every RTL result of the CAL campaign (and the published archive) into tidy CSVs.

Outputs (ieee_cal/data/):
  runs.csv      one row per run: config, r, tag, benchmark, size, status, cycles, instructions, ipc, elapsed_sec
  summary.csv   per (config, r, tag): geomean speedup vs baseline@1.0 (16x and all sizes), wins/24 at 16x, n
Re-run any time; it only reads results.
"""
import csv, glob, os, re, math, sys
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
EVAL = os.path.join(ROOT, "eval_perf_swemu")
OUT = os.path.join(ROOT, "ieee_cal", "data")
OK = ("PASSED", "COMPLETED")

def parse(path):
    d = {}
    for line in open(path, errors="replace"):
        if "=" in line:
            k, v = line.rstrip("\n").split("=", 1); d[k] = v
    return d

rows = []
# campaign + archive layout: results_rtlsim/<cfg>_mem<r>[_<tag>]/<bench>_<size>.txt
for d in glob.glob(f"{EVAL}/results_rtlsim/*_mem*"):
    name = os.path.basename(d)
    m = re.match(r"(.+)_mem([0-9.]+)(?:_(.+))?$", name)
    if not m or name.startswith("build_"): continue
    cfg, r, tag = m.group(1), m.group(2), m.group(3) or ""
    for f in glob.glob(f"{d}/*.txt"):
        b = os.path.basename(f)[:-4]
        mb = re.match(r"(.+)_(1x|4x|16x)$", b)
        if not mb: continue
        p = parse(f)
        rows.append(dict(config=cfg, r=r, tag=tag, benchmark=mb.group(1), size=mb.group(2), status=p.get("status", ""),
                         cycles=p.get("cycles", ""), instructions=p.get("instructions", ""), ipc=p.get("ipc", ""),
                         elapsed_sec=p.get("elapsed_sec", ""), mem_reads=p.get("mem_reads", ""), mem_writes=p.get("mem_writes", "")))
# scaling study layout: results_scaling/<cfg>_mem<r>_<size>/<bench>.txt
for d in glob.glob(f"{EVAL}/results_scaling/*_mem*_*x"):
    m = re.match(r"(.+)_mem([0-9.]+)_(1x|4x|16x)$", os.path.basename(d))
    if not m: continue
    for f in glob.glob(f"{d}/*.txt"):
        p = parse(f)
        rows.append(dict(config=m.group(1), r=m.group(2), tag="scaling", benchmark=os.path.basename(f)[:-4], size=m.group(3),
                         status=p.get("status", ""), cycles=p.get("cycles", ""), instructions=p.get("instructions", ""),
                         ipc=p.get("ipc", ""), elapsed_sec=p.get("elapsed_sec", ""), mem_reads="", mem_writes=""))
rows.sort(key=lambda x: (x["config"], float(x["r"]), x["tag"], x["benchmark"], x["size"]))
with open(f"{OUT}/runs.csv", "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)

# summary vs baseline@1.0 (archive, untagged)
base = {(x["benchmark"], x["size"]): int(x["cycles"]) for x in rows if x["config"] == "baseline" and x["r"] == "1.0" and x["tag"] == "" and x["status"] in OK and x["cycles"]}
def geo(xs): return math.exp(sum(map(math.log, xs)) / len(xs)) if xs else float("nan")
groups = {}
for x in rows:
    if x["status"] in OK and x["cycles"] and (x["benchmark"], x["size"]) in base:
        groups.setdefault((x["config"], x["r"], x["tag"]), []).append((x["benchmark"], x["size"], base[(x["benchmark"], x["size"])] / int(x["cycles"])))
summ = []
for (cfg, r, tag), xs in sorted(groups.items(), key=lambda kv: (kv[0][0], float(kv[0][1]), kv[0][2])):
    s16 = [v for b, s, v in xs if s == "16x"]
    summ.append(dict(config=cfg, r=r, tag=tag, n_runs=len(xs), n_16x=len(s16), geomean_all=round(geo([v for _, _, v in xs]), 4),
                     geomean_16x=round(geo(s16), 4), wins_16x=sum(1 for v in s16 if v > 1.0),
                     min_16x=round(min(s16), 3) if s16 else "", max_16x=round(max(s16), 3) if s16 else ""))
with open(f"{OUT}/summary.csv", "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=list(summ[0].keys())); w.writeheader(); w.writerows(summ)
print(f"runs: {len(rows)}  summary rows: {len(summ)}  -> {OUT}")
