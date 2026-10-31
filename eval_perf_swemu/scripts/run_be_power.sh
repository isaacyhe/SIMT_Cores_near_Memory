#!/bin/bash
# Power sweep for vortex_baseline_be (byte-enable fakeram), 10 windows x 1k ops
# into the kernel. Mirrors run_gate_vcd_power.sh but: _be ODB, RT_GATE=runtime_gate_be,
# WIN=1000, 10 evenly-spaced phases, floor 1000 (1k windows). Phase2 = OpenROAD power.
set -u
MODE="${1:-go}"; NJOBS="${2:-6}"
EVAL_DIR=/home/he/GPU_and_PNM/eval_perf_swemu
ROOT_DIR=/home/he/GPU_and_PNM
VORTEX_DIR="$ROOT_DIR/vortex"
RT_GATE="${RT_GATE:-$VORTEX_DIR/runtime_gate_be}"
OCL="$VORTEX_DIR/tests/opencl"
OUT="$EVAL_DIR/results_vcd_power_be"; VCDDIR="$OUT/vcds"; mkdir -p "$VCDDIR"
ORD="${ORD:-/home/he/OpenROAD/build/bin/openroad}"
BATCH_TCL="$ROOT_DIR/spr_eval/scripts/batch_vcd_power.tcl"
ODB="${ODB:-$ROOT_DIR/OpenROAD-flow-scripts/flow/results/asap7/vortex_baseline_be/base/6_final.odb}"
SIMX="$EVAL_DIR/results_simx/baseline_mem1.0"
BENCHES=(bfs blackscholes bs conv3 dotproduct gather guassian histogram kmeans lbm \
         memcopy mlp nearn nw psort psum saxpy sfilter sgemm3 spmv stencil transpose uni vecadd)
[ -n "${BENCHES_OVERRIDE:-}" ] && BENCHES=($BENCHES_OVERRIDE)
[ "$MODE" = smoke ] && BENCHES=(vecadd sgemm3)
WIN="${VCD_WINDOW:-1000}"                     # 1k ops per sample
# 10 evenly-spaced windows into the kernel (0.05..0.95), large cap so fraction dominates
PHASE_SPECS="${PHASE_SPECS:-0.05 999999 0.15 999999 0.25 999999 0.35 999999 0.45 999999 0.55 999999 0.65 999999 0.75 999999 0.85 999999 0.95 999999}"
FLOOR="${FLOOR:-1000}"
gen_one () {
  local b="$1" d="$OCL/$1"; [ -d "$d" ] || { echo "  skip $b"; return; }
  local cyc; cyc=$(grep -oP 'cycles=\K\d+' "$SIMX/$b.txt" 2>/dev/null | tail -1); cyc="${cyc:-40000}"
  local idx=0 set_specs=($PHASE_SPECS) i frac cap wu
  for ((i=0; i<${#set_specs[@]}; i+=2)); do
    frac="${set_specs[i]}"; cap="${set_specs[i+1]}"
    wu=$(awk -v c="$cyc" -v f="$frac" -v cap="$cap" -v w="$WIN" -v fl="$FLOOR" 'BEGIN{
        u=int(f*c); if(u>cap)u=cap; if(u<fl)u=fl;
        if(u+w>c){print -1}else{print u}}')
    [ "$wu" = "-1" ] && { idx=$((idx+1)); continue; }
    local pc="/tmp/pcbe_${b}_${idx}"; rm -rf "$pc"; mkdir -p "$pc"
    ( cd "$d" && rm -f trace.vcd
      timeout 1200 env VCD_EARLY_EXIT=1 VCD_WARMUP="$wu" VCD_WINDOW="$WIN" \
        POCL_KERNEL_CACHE=0 POCL_CACHE_DIR="$pc" \
        make run-rtlsim VORTEX_HOME="$VORTEX_DIR" VORTEX_RT_PATH="$RT_GATE" \
        TOOLDIR="$ROOT_DIR/toolchain" MARCH=rv32imf MABI=ilp32f PERF=1 >/tmp/bevcd_${b}_p${idx}.log 2>&1 )
    rm -rf "$pc"
    [ -f "$d/trace.vcd" ] && { mv -f "$d/trace.vcd" "$VCDDIR/${b}__p${idx}.vcd"; echo "  ok ${b} p${idx} wu=$wu"; } || echo "  FAIL ${b} p${idx}"
    idx=$((idx+1))
  done
}
export -f gen_one; export OCL VORTEX_DIR RT_GATE ROOT_DIR VCDDIR SIMX WIN PHASE_SPECS FLOOR
echo ">>> Phase 1: ${#BENCHES[@]} benchmarks x 10 windows (parallel=$NJOBS)..."
printf '%s\n' "${BENCHES[@]}" | xargs -P "$NJOBS" -I{} bash -c 'gen_one "$@"' _ {}
echo ">>> Phase 1 done: $(ls "$VCDDIR"/*.vcd 2>/dev/null | wc -l) VCDs"
NWORK="${NWORK:-4}"; WROOT="$OUT/_p2"; rm -rf "$WROOT"; mkdir -p "$WROOT"
mapfile -t ALLV < <(ls "$VCDDIR"/*.vcd 2>/dev/null)
for i in "${!ALLV[@]}"; do w=$(( i % NWORK )); mkdir -p "$WROOT/w$w"; ln -sf "${ALLV[i]}" "$WROOT/w$w/"; done
pids=()
for w in $(seq 0 $((NWORK-1))); do [ -d "$WROOT/w$w" ] || continue
  ODB="$ODB" VCDDIR="$WROOT/w$w" ACT="${ACT:-0.1}" timeout 7200 "$ORD" -exit -no_init "$BATCH_TCL" >"$OUT/batch_power_w$w.log" 2>&1 & pids+=($!); done
for p in "${pids[@]}"; do wait "$p"; done
cat "$OUT"/batch_power_w*.log > "$OUT/batch_power.log" 2>/dev/null; rm -rf "$WROOT"
RES="$OUT/be_power.csv"; PHASES="$OUT/be_per_phase.csv"
echo "benchmark,phase,vcd_power_mW" > "$PHASES"
awk '/VCDPOW_BEGIN/{k=$2} /^Total/ && k {printf "%s,%.2f\n", k, $5*1000; k=""}' "$OUT/batch_power.log" | sed 's/__p/,/' >> "$PHASES"
echo "benchmark,vcd_power_mW,n_samples" > "$RES"
awk -F, 'NR>1{b=$1; sum[b]+=$3; n[b]++} END{for(b in sum) printf "%s,%.2f,%d\n", b, sum[b]/n[b], n[b]}' "$PHASES" | sort >> "$RES"
echo "=== _be per-benchmark (10-sample avg) -> $RES ==="; cat "$RES"
