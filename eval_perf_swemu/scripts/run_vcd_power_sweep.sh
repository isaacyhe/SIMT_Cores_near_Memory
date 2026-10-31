#!/bin/bash
# ============================================================================
# Sweep A --- coarse-vs-VCD/SAIF power ACCURACY calibration, baseline x benchmarks
# ----------------------------------------------------------------------------
# For each benchmark: RTL-sim VCD (VCD-only build, no debug-text firehose) ->
# OpenROAD read_power_activities -vcd @ REAL 500 MHz -> report_power.
# Compared against the coarse activity-model power. Answers 30C-R5.
#
# Tier 1 (this script): benchmarks with <= MAXCYC cycles -> FULL trace (reliable).
# Tier 2 (big benchmarks): need windowing (handled separately).
#
# Key fixes baked in:
#  * VCD-only: DBG_TRACE_FLAGS= (no per-cycle debug text -> sim is fast).
#  * VORTEX_HOME set (avoids stale /home/user path).
#  * OpenROAD clock overridden to 500 MHz in vcd_power.tcl (not the 2ps SDC).
#  * VCD deleted after each OpenROAD run (VCDs are GB-scale).
#
# Usage: ./run_vcd_power_sweep.sh [smoke|go]
# ============================================================================
set -u
MODE="${1:-go}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EVAL_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(dirname "$EVAL_DIR")"
VORTEX_DIR="$ROOT_DIR/vortex"
OUT="$EVAL_DIR/results_vcd_power"; mkdir -p "$OUT"
ORD=/usr/local/bin/openroad
TCL="$ROOT_DIR/spr_eval/scripts/vcd_power.tcl"
MAXCYC=300000   # full-trace cap; bigger benchmarks deferred to windowed tier

# Tier-1 benchmarks (<=~250k cycles) + their 1x default args (empty = Makefile default)
SMALL=(vecadd psum psort sfilter gather saxpy conv3 sgemm3 bs memcopy uni spmv dotproduct)
[ "$MODE" = smoke ] && SMALL=(vecadd sgemm3)

echo "=== Sweep A: VCD-vs-coarse power, baseline, ${#SMALL[@]} benchmarks (mode=$MODE) ==="

# --- build rtlsim ONCE: VCD-only, full trace, MEM_CLOCK_RATIO=1.0 ---
echo ">>> building rtlsim (VCD-only, no debug text)..."
# never while an rtlsim campaign uses runtime/librtlsim.so (energy rows check the library md5)
exec 8>"$VORTEX_DIR/runtime/.rtlsim_campaign.lock"
flock -sn 8 || { echo "ERROR: an rtlsim campaign holds $VORTEX_DIR/runtime/.rtlsim_campaign.lock; build in another tree or wait"; exit 1; }
make -C "$VORTEX_DIR/sim/rtlsim" DESTDIR="$VORTEX_DIR/runtime" VORTEX_HOME="$VORTEX_DIR" \
  CONFIGS="-DMEM_CLOCK_RATIO=1.0" DEBUG=1 DBG_TRACE_FLAGS= PERF=1 \
  "$VORTEX_DIR/runtime/librtlsim.so" >/tmp/vcdsweep_build.log 2>&1 || { echo "BUILD FAIL"; exit 1; }
make -C "$VORTEX_DIR/runtime/rtlsim" DESTDIR="$VORTEX_DIR/runtime" VORTEX_HOME="$VORTEX_DIR" \
  CONFIGS="-DMEM_CLOCK_RATIO=1.0" DEBUG=1 DBG_TRACE_FLAGS= PERF=1 >>/tmp/vcdsweep_build.log 2>&1 || { echo "BUILD FAIL2"; exit 1; }
echo ">>> build OK"

RESULTS="$OUT/vcd_vs_coarse.csv"
echo "benchmark,cycles,vcd_power_mW,vcd_internal_mW,vcd_switching_mW,vcd_leakage_mW" > "$RESULTS"

for b in "${SMALL[@]}"; do
  bdir="$VORTEX_DIR/tests/opencl/$b"
  [ -d "$bdir" ] || { echo "  skip $b (no dir)"; continue; }
  echo ">>> $b: generating VCD..."
  ( cd "$bdir" && rm -f trace.vcd *.cc.o *.cc.d 2>/dev/null
    timeout 600 make run-rtlsim VORTEX_HOME="$VORTEX_DIR" MARCH=rv32imf MABI=ilp32f PERF=1 \
      TOOLDIR="$ROOT_DIR/toolchain" >/tmp/vcdsweep_${b}_run.log 2>&1 )
  vcd="$bdir/trace.vcd"
  if [ ! -f "$vcd" ]; then echo "  $b: NO VCD (see /tmp/vcdsweep_${b}_run.log)"; continue; fi
  sz=$(stat -c%s "$vcd"); echo "  $b: VCD $(( sz/1000000 )) MB -> OpenROAD power..."
  CFG=baseline VCD="$vcd" SCOPE=TOP.rtlsim_shim.vortex \
    timeout 900 "$ORD" -exit -no_init "$TCL" >"/tmp/vcdsweep_${b}_ord.log" 2>&1
  # parse the Total line (Watts) -> mW
  tot=$(grep -A12 "report_power (VCD" "/tmp/vcdsweep_${b}_ord.log" | awk '/^Total/{print $5}')
  intl=$(grep -A12 "report_power (VCD" "/tmp/vcdsweep_${b}_ord.log" | awk '/^Total/{print $2}')
  sw=$(grep -A12 "report_power (VCD" "/tmp/vcdsweep_${b}_ord.log" | awk '/^Total/{print $3}')
  lk=$(grep -A12 "report_power (VCD" "/tmp/vcdsweep_${b}_ord.log" | awk '/^Total/{print $4}')
  cyc=$(grep -oP 'PERF: instrs=\d+, cycles=\K\d+' "/tmp/vcdsweep_${b}_run.log" | tail -1)
  tot_mW=$(awk "BEGIN{printf \"%.2f\", ($tot)*1000}" 2>/dev/null)
  echo "$b,${cyc:-?},${tot_mW:-?},$(awk "BEGIN{printf \"%.2f\",($intl)*1000}" 2>/dev/null),$(awk "BEGIN{printf \"%.2f\",($sw)*1000}" 2>/dev/null),$(awk "BEGIN{printf \"%.4f\",($lk)*1000}" 2>/dev/null)" >> "$RESULTS"
  echo "  $b: VCD power = ${tot_mW} mW"
  rm -f "$vcd"   # free disk (GB-scale)
done

echo "=== done. results: $RESULTS ==="
cat "$RESULTS"
