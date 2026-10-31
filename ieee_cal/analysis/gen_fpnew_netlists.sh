#!/bin/bash
# FPnew netlists for re-SPR (Oct 24): gen_be_projects recipe + -DFPU_FPNEW + cvfpu includes + upstream sim-task strip.
set -u
ROOT=/home/he/workspace/GPU_and_PNM; HW=$ROOT/vortex/hw; CV=$ROOT/vortex/third_party/cvfpu/src; CFG=$ROOT/spr_eval/configs; BUILD=${BUILD:-$ROOT/spr_eval/build}
export PATH=$ROOT/toolchain/sv2v/bin:$PATH
for D in "$@"; do
  B=$BUILD/${D}_be_fpnew; [ -f $B/project.v ] && { echo "$D: EXISTS, skip"; continue; }; mkdir -p $B/src; DEF=""
  while IFS= read -r line; do
    if [[ "$line" =~ ^\`define[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)([[:space:]]+(.+))?$ ]]; then
      n="${BASH_REMATCH[1]}"; v="${BASH_REMATCH[3]}"; [ "$n" = VX_CONFIG_OVERRIDE_VH ] && continue
      if [ -n "$v" ]; then DEF="$DEF -D$n=$v"; else DEF="$DEF -D$n"; fi; fi
  done < $CFG/$D/VX_config_override.vh
  CF="-DSYNTHESIS -DYOSYS -DXLEN_32 -DUSE_FAKERAM -DFPU_FPNEW $DEF -I$HW/rtl -I$HW/rtl/libs -I$HW/rtl/interfaces -I$HW/rtl/core -I$HW/rtl/mem -I$HW/rtl/cache -I$HW/rtl/fpu"
  CF="$CF -I$CV -I$CV/common_cells/include -I$CV/common_cells/src -I$CV/fpu_div_sqrt_mvp/hdl"
  E9=$ROOT/vortex/third_party/cvfpu/vendor/opene906/E906_RTL_FACTORY/gen_rtl; CF="$CF -I$E9/fdsu/rtl -I$E9/fpu/rtl -I$E9/clk/rtl"   # T-Head div/sqrt (default)
  CF="$CF ${EXTRA_FLAGS:-}"   # optional extra -D/-I (e.g. T-Head divsqrt variant); empty by default
  t0=$(date +%s)
  ( cd $B && $HW/scripts/gen_sources.sh -P $CF -Csrc -Osources.txt > gen_sources.log 2>&1 ) || { echo "$D: gen_sources FAILED"; continue; }
  ( cd $B && /home/he/workspace/GPU_and_PNM/ieee_cal/analysis/sv2v_sorted.sh -tVortex -Isrc -oproject.v > sv2v.log 2>&1 ) || { echo "$D: sv2v FAILED"; continue; }
  sed -ri '/^[[:space:]]*[$](finish|display|fatal|error|warning|info|stop)/d' $B/project.v
  printf "%s: OK %s lines %ss | fpnew_top=%s stub=%s simtasks=%s th32=%s | macros: %s\n" $D "$(wc -l < $B/project.v)" "$(( $(date +%s)-t0 ))" \
    "$(grep -c '^module fpnew_top' $B/project.v)" "$(grep -c 'shift_reg_stub' $B/project.v)" \
    "$(grep -c -E '[$](finish|display|fatal|error|warning|info|stop)' $B/project.v)" "$(grep -c 'pa_fdsu_top' $B/project.v)" \
    "$(grep -oE '^\s*fakeram7_[0-9]+x32_be ' $B/project.v | sort | uniq -c | awk '{printf "%sx%s ", $1, $2}')"
done
echo NETLISTS_DONE
