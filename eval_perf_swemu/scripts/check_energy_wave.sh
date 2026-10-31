#!/bin/bash
# CAL energy campaign completeness check. Usage: check_energy_wave.sh <jobs_file> [results_tag=energy]
# A run is ACCEPTED only if row_reject_reason (row_accept.sh) finds nothing (status, counters, build id, pinned library, clean
# build, the row matches its job line, real-RTL flags, results present and intact). ENERGY_BUILD_ID may be given in the env.
# Prints a summary and every run that is missing or rejected (with status / ctr_status / ctr_error); exit 0 only if all accepted.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EVAL_DIR="$(dirname "$SCRIPT_DIR")"
JOBS="${1:?usage: check_energy_wave.sh <jobs_file> [results_tag]}"
TAG="${2:-energy}"
source "$SCRIPT_DIR/check_realrtl.sh"
realrtl_reexec_clean "$SCRIPT_DIR/$(basename "$0")" "$@"   # env -i with the allowlist (ENERGY_BUILD_ID kept)
source "$SCRIPT_DIR/row_accept.sh"
[ -z "$(realrtl_env_dirty)" ] || { echo "FAIL: environment not clean after re-exec: $(realrtl_env_dirty | tr '\n' ' ')"; exit 1; }
ROOT="$(dirname "$EVAL_DIR")"
# workload files must still match the committed manifest
if [ "$(basename "$JOBS")" = "jobs_energy_wave1.txt" ]; then
    mdiff=$(LC_ALL=C comm -3 <("$SCRIPT_DIR/workload_manifest.sh" "$JOBS" | LC_ALL=C sort) <(LC_ALL=C sort "$ROOT/ieee_cal/analysis/workload_manifest_wave1.txt"))
else
    mdiff=$(LC_ALL=C comm -23 <("$SCRIPT_DIR/workload_manifest.sh" "$JOBS" | LC_ALL=C sort) <(LC_ALL=C sort "$ROOT/ieee_cal/analysis/workload_manifest_wave1.txt"))
fi
MANIFEST_OK=1
# provenance: the job file, its energy configs and the map must be committed (as the launcher requires)
cdirty=$(git -C "$ROOT" status --porcelain -- ieee_cal/analysis/energy_map.tsv "$(realpath --relative-to="$ROOT" "$JOBS")" \
         $(awk '{print "eval_perf_swemu/configs/"$1"/config.mk"}' "$JOBS" | sort -u) 2>&1) || cdirty="git error: $cdirty"
git -C "$ROOT" ls-files --error-unmatch "$(realpath --relative-to="$ROOT" "$JOBS")" >/dev/null 2>&1 || cdirty="$cdirty job file not committed"
[ -z "$cdirty" ] || { echo "FAIL: uncommitted job file, configs or map: $(echo $cdirty)"; MANIFEST_OK=0; }
[ -z "$mdiff" ] || { echo "FAIL: workload files differ from the committed manifest: $(echo "$mdiff" | head -3 | tr '\n' ' ')"; MANIFEST_OK=0; }
BUILD_ID="${ENERGY_BUILD_ID:-$(sim_build_id "$ROOT/vortex")}"
LIB12=${REALRTL_LIB_MD5:0:12}   # the validated library, not whatever is installed now
[ "$(md5sum < "$ROOT/vortex/third_party/ramulator/libramulator.so" | cut -c1-32)" = "$REALRTL_LIB_MD5" ] || echo "WARNING: installed libramulator.so is not the validated build (rows are checked against $LIB12)"
echo "checking against build id $BUILD_ID, libramulator $LIB12"
total=0; ok=0; bad=0; LIBS_SEEN=$(mktemp)
while read -r cfg r bench args size; do
    [ -z "$cfg" ] && continue
    total=$((total + 1))
    res="$EVAL_DIR/results_rtlsim/${cfg}_mem${r}_${TAG}/${bench}_${size}.txt"
    why=$(row_reject_reason "$res" "$BUILD_ID" "$LIB12" "$cfg" "$r" "$bench" "$args" "$size" "$(config_override "$EVAL_DIR" "$cfg")" | tr '\n' ';')
    if [ -z "$why" ]; then ok=$((ok + 1)); echo "$cfg $r $(grep -m1 -oP '^lib_md5_stamp=\K.*' "$res")" >> "$LIBS_SEEN"; else echo "REJECTED $cfg r=$r $bench: $why"; bad=$((bad + 1)); fi
done < "$JOBS"
# one library per (config, ratio) group: every accepted run of a group ran on the same build
LIB_OK=1
multi=$(sort -u "$LIBS_SEEN" | awk '{g[$1" "$2]++} END{for(k in g) if(g[k]>1) print k}')
[ -z "$multi" ] || { echo "FAIL: groups whose accepted runs used different libraries: $(echo $multi)"; LIB_OK=0; }
rm -f "$LIBS_SEEN"
echo "accepted $ok / $total ($bad missing or rejected)"
[ "$ok" = "$total" ] && [ "$MANIFEST_OK" = "1" ] && [ "$LIB_OK" = "1" ]
