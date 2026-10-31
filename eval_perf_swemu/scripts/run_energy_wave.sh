#!/bin/bash
# CAL per-run energy campaign launcher (Oct 25). Usage: run_energy_wave.sh <jobs_file> [parallel=8] [--cloud]
# --cloud (Oct 27): one isolated worker per configuration group on a cloud node (own tree copy, /tmp and PID namespace,
# see wave1/wave_node.sh); the parallel limit is then 24 (one group) instead of the local host's 8.
# Refuses to start unless every precondition holds; then runs run_parallel_rtlsim.sh with the energy environment:
#   VX_REALRTL=1 (real-RTL guard: -DFPU_FPNEW -DDPI_DISABLE, built library contains FPnew/T-Head)
#   VX_CMDSTATS_ON=1 (RTL activity counters + timing/shadow DRAM statistics; incomplete files -> CTR_MISSING)
#   RESULTS_TAG=energy (results_rtlsim/<config>_mem<r>_energy/, never mixed with published results)
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EVAL_DIR="$(dirname "$SCRIPT_DIR")"
ROOT="$(dirname "$EVAL_DIR")"
JOBS="${1:?usage: run_energy_wave.sh <jobs_file> [parallel]}"
PAR="${2:-8}"
MODE="${3:-}"
MAP="$ROOT/ieee_cal/analysis/energy_map.tsv"
source "$SCRIPT_DIR/check_realrtl.sh"   # helpers (also config_fields from row_accept.sh) before any check uses them
realrtl_reexec_clean "$SCRIPT_DIR/$(basename "$0")" "$@"   # from here on: env -i with the allowlist only (FORCE_RERUN, VX_RUN_TIMEOUT kept)
source "$SCRIPT_DIR/row_accept.sh"
LIB="$ROOT/vortex/third_party/ramulator/libramulator.so"
fail() { echo "REFUSED: $*"; exit 1; }

[ -f "$JOBS" ] || fail "jobs file not found: $JOBS"
[ -f "$MAP" ] || fail "energy map not found: $MAP"
case "$MODE" in
    "")      [ "$PAR" -le 8 ] || fail "local limit is 8 concurrent simulations" ;;
    --cloud) [ "$PAR" -le 24 ] || fail "cloud worker limit is 24 concurrent simulations (one group)" ;;
    *)       fail "unknown option: $MODE (only --cloud)" ;;
esac
# every job uses an energy config listed in the map, at 16x
bad=$(awk -v M="$MAP" 'BEGIN{while((getline l < M)>0){split(l,f,"\t"); if(f[1]!~/^#/) ok[f[2]]=1}}
      NF<5 || !($1 in ok) || $5!="16x" {print NR": "$0}' "$JOBS" | head -3)
[ -z "$bad" ] || fail "jobs not in the energy map or not 16x: $bad"
# every energy config yields the real-RTL flags when parsed the way run_single_rtlsim.sh parses it (line by line)
for cfg in $(awk '{print $1}' "$JOBS" | sort -u); do
    ov=""
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*VX_CONFIG_OVERRIDE[[:space:]]*=[[:space:]]*(.+)$ ]] && ov="${BASH_REMATCH[1]}"
    done < "$EVAL_DIR/configs/$cfg/config.mk"
    [[ " $ov " == *" -DFPU_FPNEW "* && " $ov " == *" -DDPI_DISABLE "* ]] || fail "$cfg: VX_CONFIG_OVERRIDE does not parse to the real-RTL flags ('$ov')"
    # stock benchmarks, or soft-math benchmarks (hashed into the build id) with the replaced hardware removed (softmath_reason)
    cfl=$(config_fields "$EVAL_DIR" "$cfg"); cf=$(cut -f3 <<< "$cfl"); um=$(cut -f4 <<< "$cfl")   # cut keeps empty fields (read would collapse tabs)
    why=$(softmath_reason "$um" "$cf" "$ov"); [ -z "$why" ] || fail "$cfg: USE_MODIFIED_BENCHMARKS=$um CFLAGS='$cf': $(echo $why)"
done
# kernel runtimes (Oct 28): both prebuilt libraries are exactly the validated files (archives carry timestamps, so a rebuild changes
# the md5: copy these files, never rebuild them on another host); the softdiv vx_spawn executes no div/rem, the stock one does
STOCK_KLIB_MD5=82f2776914e33afc7d0faf6bb2766369   # vortex/kernel/libvortex.a (Oct 28: vx_spawn per-task indexing by reciprocals; other members unchanged since Oct 23)
SOFT_KLIB_MD5=238662f02c8ff86bd936e1ae2a58bf79    # vortex/kernel/softdiv/libvortex.a (same, reciprocals prepared by the branch-free soft division)
[ "$(md5sum < "$ROOT/vortex/kernel/libvortex.a" | cut -c1-32)" = "$STOCK_KLIB_MD5" ] || fail "vortex/kernel/libvortex.a is not the validated runtime ($STOCK_KLIB_MD5)"
[ "$(md5sum < "$ROOT/vortex/kernel/softdiv/libvortex.a" 2>/dev/null | cut -c1-32)" = "$SOFT_KLIB_MD5" ] || fail "vortex/kernel/softdiv/libvortex.a is not the validated soft-IDIV runtime ($SOFT_KLIB_MD5)"
OD="$ROOT/toolchain/llvm-vortex/bin/llvm-objdump"; KT=$(mktemp -d) || fail "mktemp failed"
# (no helper function: the re-exec environment check allows only the realrtl functions)
dis_stock=$( (cd "$KT" && ar x "$ROOT/vortex/kernel/libvortex.a" vx_spawn.c.o) && [ -s "$KT/vx_spawn.c.o" ] && "$OD" -d "$KT/vx_spawn.c.o") \
    || { rm -rf "$KT"; fail "cannot disassemble vx_spawn.c.o of kernel/libvortex.a"; }
rm -f "$KT/vx_spawn.c.o"
dis_soft=$( (cd "$KT" && ar x "$ROOT/vortex/kernel/softdiv/libvortex.a" vx_spawn.c.o) && [ -s "$KT/vx_spawn.c.o" ] && "$OD" -d "$KT/vx_spawn.c.o") \
    || { rm -rf "$KT"; fail "cannot disassemble vx_spawn.c.o of kernel/softdiv/libvortex.a"; }
rm -rf "$KT"
nd_stock=$(grep -cE '\s(div|divu|rem|remu)\s' <<< "$dis_stock"); nd_soft=$(grep -cE '\s(div|divu|rem|remu)\s' <<< "$dis_soft"); nm_soft=$(grep -cE '\smulhu\s' <<< "$dis_soft")
[ "$nd_soft" = 0 ] && [ "$nm_soft" -gt 0 ] && [ "$nd_stock" -gt 0 ] || fail "kernel runtimes: softdiv vx_spawn div/rem=$nd_soft mulhu=$nm_soft (expected 0, >0); stock div/rem=$nd_stock (expected >0)"
# installed Ramulator is exactly the validated build (ramulator branch fpnew-energy a986652)
LIB_MD5=$REALRTL_LIB_MD5
[ "$(md5sum < "$LIB" | cut -c1-32)" = "$LIB_MD5" ] || fail "installed libramulator.so is not the validated build ($LIB_MD5)"
for sym in VxCmdStats VxPhysRefresh vx_phys_refresh_enable; do
    nm -DC "$LIB" | grep -q "$sym" || fail "installed libramulator.so lacks $sym"
done
grep -aq "open_ticks_run=" "$LIB" || fail "installed libramulator.so lacks open_ticks_run"
# the simulation sources must be committed (provenance), and no backup or stray source in the build paths
# prebuilt libraries (rebuilt only if missing) must be newer than their sources (their md5 is in the build id, not their freshness)
stale_lib=$(find "$ROOT/vortex/kernel/src" "$ROOT/vortex/kernel/include" "$ROOT/vortex/hw/VX_config.h" "$ROOT/vortex/hw/VX_types.h" \
                 -type f -newer "$ROOT/vortex/kernel/libvortex.a" | head -2;
            find "$ROOT/vortex/kernel/src" "$ROOT/vortex/kernel/include" "$ROOT/vortex/kernel/softdiv/Makefile" "$ROOT/vortex/hw/VX_config.h" "$ROOT/vortex/hw/VX_types.h" \
                 -type f -newer "$ROOT/vortex/kernel/softdiv/libvortex.a" 2>/dev/null | head -2; [ -f "$ROOT/vortex/kernel/softdiv/libvortex.a" ] || echo "kernel/softdiv/libvortex.a missing";
            find "$ROOT/vortex/runtime/stub" "$ROOT/vortex/runtime/common" "$ROOT/vortex/runtime/include" "$ROOT/vortex/hw/VX_config.h" \
                 "$ROOT/vortex/hw/VX_types.h" "$ROOT/vortex/sim/common/mem_alloc.h" -type f -newer "$ROOT/vortex/runtime/libvortex.so" | head -2)
[ -z "$stale_lib" ] || fail "prebuilt libvortex.a / libvortex.so older than their sources (rebuild them): $(echo $stale_lib)"
# automatic system upgrades during the ~72 h wave would change the hashed toolchain (g++, libstdc++, verilator, python3)
# and stop the campaign (fail-closed) with every finished row stale. Oct 25: the user chose to keep upgrades on -> warn only
if command -v systemctl >/dev/null && systemctl is-active --quiet apt-daily-upgrade.timer apt-daily.timer 2>/dev/null; then
    echo "WARNING: automatic apt upgrades are active; an upgrade of g++/libstdc++/verilator/python3 during the wave stops it"
    echo "         (build id changes; finished rows go stale). To avoid: sudo systemctl stop apt-daily-upgrade.timer apt-daily.timer"
fi
dirty=$(sim_tree_dirty "$ROOT/vortex")
[ -z "$dirty" ] || fail "uncommitted simulation sources: $(echo $dirty)"
# workload data inputs are pinned by the committed manifest (they are not in git)
MANIFEST="$ROOT/ieee_cal/analysis/workload_manifest_wave1.txt"
[ -f "$MANIFEST" ] || fail "workload manifest missing: $MANIFEST"
# both directions: a changed, added or deleted file all count (the committed manifest must cover exactly the job list's files)
if [ "$(basename "$JOBS")" = "jobs_energy_wave1.txt" ]; then
    mdiff=$(LC_ALL=C comm -3 <("$SCRIPT_DIR/workload_manifest.sh" "$JOBS" | LC_ALL=C sort) <(LC_ALL=C sort "$MANIFEST"))
else   # a subset of the wave: every live entry must be in the manifest
    mdiff=$(LC_ALL=C comm -23 <("$SCRIPT_DIR/workload_manifest.sh" "$JOBS" | LC_ALL=C sort) <(LC_ALL=C sort "$MANIFEST"))
fi
[ -z "$mdiff" ] || fail "workload files differ from the committed manifest: $(echo "$mdiff" | head -3 | tr '\n' ' ')"
BUILD_ID=$(sim_build_id "$ROOT/vortex") || fail "cannot compute the build id: $BUILD_ID"
export CAMPAIGN_BUILD_ID="$BUILD_ID"   # frozen: every group and every run refuses a different id
# the job's energy configs and the map must be committed (they are checked per row, not hashed into the build id)
cfgdirty=$(git -C "$ROOT" status --porcelain -- ieee_cal/analysis/energy_map.tsv "$(realpath --relative-to="$ROOT" "$JOBS")" $(awk '{print "eval_perf_swemu/configs/"$1"/config.mk"}' "$JOBS" | sort -u) 2>&1) \
    || fail "git status of the energy configs failed: $cfgdirty"
[ -z "$cfgdirty" ] || fail "uncommitted job file, energy configs or map: $(echo $cfgdirty)"
git -C "$ROOT" ls-files --error-unmatch "$(realpath --relative-to="$ROOT" "$JOBS")" >/dev/null 2>&1 || fail "job file is not committed: $JOBS"
# no other campaign may run in this tree (each group rebuilds the shared runtime/librtlsim.so)
# (match running runner scripts by argv, not any command line that merely mentions them)
running=$(ps -eo pid=,args= | awk '$2 ~ /(^|\/)(ba)?sh$/ && $3 ~ /run_(parallel|single)_rtlsim(_memctr)?\.sh$/ {print $1}')
[ -z "$running" ] || fail "another campaign is running in this tree (pids: $(echo $running))"

export VX_REALRTL=1 VX_CMDSTATS_ON=1 RESULTS_TAG=energy
export VX_RUN_TIMEOUT="${VX_RUN_TIMEOUT:-259200}"  # 72 h per run: the longest published 16x run is 7.4 h and energy mode measured 0.37-3.87x
                                                   # the published wall times (groups run one at a time: a hung run stalls the campaign this long)
unset VX_DRAM_SHADOW_MODE VX_CTR_ON VX_DRAM_TRACE VX_CTR_FILE VX_DRAM_CMDSTATS
[ -z "$(realrtl_env_dirty)" ] || fail "environment not clean after re-exec: $(realrtl_env_dirty | tr '\n' ' ')"

# resume: skip runs that already have an accepted result (status PASSED/COMPLETED, ctr_status=OK, realrtl_verified=1)
TODO="$EVAL_DIR/results_rtlsim/.energy_todo_$(basename "$JOBS" .txt).lst"
mkdir -p "$EVAL_DIR/results_rtlsim"
: > "$TODO"
done_n=0; held=0
while read -r cfg r bench args size; do
    [ -z "$cfg" ] && continue
    res="$EVAL_DIR/results_rtlsim/${cfg}_mem${r}_${RESULTS_TAG}/${bench}_${size}.txt"
    why=$(row_reject_reason "$res" "$BUILD_ID" "${LIB_MD5:0:12}" "$cfg" "$r" "$bench" "$args" "$size" "$(config_override "$EVAL_DIR" "$cfg")")
    if [ -z "$why" ]; then done_n=$((done_n + 1)); continue; fi
    # a current-build row that ran fine but fails acceptance is never silently rerun (it would fail the same way; it may be a checker bug)
    if [ -f "$res" ] && grep -qxF "build_id=$BUILD_ID" "$res" && grep -qE '^status=(PASSED|COMPLETED)$' "$res" && grep -qx 'ctr_status=OK' "$res" \
       && [ "${FORCE_RERUN:-0}" != "1" ]; then
        held=$((held + 1)); echo "HELD $cfg r=$r $bench: $(echo "$why" | tr '\n' ';')"; continue
    fi
    # a current-build run that timed out or failed is not rerun silently (a timeout costs up to VX_RUN_TIMEOUT again)
    if [ -f "$res" ] && grep -qxF "build_id=$BUILD_ID" "$res" && { ! grep -qE '^status=(PASSED|COMPLETED)$' "$res" || ! grep -qx 'ctr_status=OK' "$res"; } \
       && [ "${FORCE_RERUN:-0}" != "1" ]; then
        held=$((held + 1)); echo "HELD $cfg r=$r $bench: current-build run ended $(grep -m1 '^status=' "$res") $(grep -m1 '^ctr_status=' "$res"); set FORCE_RERUN=1 to rerun"; continue
    fi
    echo "$cfg $r $bench $args $size" >> "$TODO"
done < "$JOBS"
# finished rows from another build would be silently rerun and overwritten: refuse unless FORCE_RERUN=1
stale=$(grep -lE '^build_id=' "$EVAL_DIR"/results_rtlsim/*_"$RESULTS_TAG"/*.txt 2>/dev/null | xargs -r grep -LxF "build_id=$BUILD_ID" | head -3)
if [ -n "$stale" ] && [ "${FORCE_RERUN:-0}" != "1" ]; then
    fail "existing $RESULTS_TAG rows were made by another build (e.g. $(echo $stale)); set FORCE_RERUN=1 to rerun them"
fi
[ "$held" = "0" ] || fail "$held current-build rows are held (listed above: ran fine but fail acceptance, or timed out / failed); fix the cause or set FORCE_RERUN=1"
echo "build id $BUILD_ID"
echo "energy wave: $JOBS ($(wc -l < "$JOBS") runs; $done_n already accepted, $(wc -l < "$TODO") to run), parallel=$PAR, RESULTS_TAG=$RESULTS_TAG, timeout=${VX_RUN_TIMEOUT}s"
[ -s "$TODO" ] || { echo "nothing to run"; exit 0; }
exec "$SCRIPT_DIR/run_parallel_rtlsim.sh" "$PAR" "$TODO"
