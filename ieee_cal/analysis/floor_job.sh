#!/bin/bash
#SBATCH -p genoa
#SBATCH -N 1
#SBATCH -c 8
#SBATCH -t 06:00:00
#SBATCH -o ${CLOUD_ROOT}/logs/floor_%j.out
# Per-design power floor (ENERGY_PLAN D3/W3, GATE_TABLE): TT libs + FakeRAM libs, routed odb + spef, propagated clock at the
# design's sign-off period and odb from signoff.tsv (default 2000 ps, 6_final.odb). Two reports per design:
#  F (floor): every non-clock net static (global and input activity 0). What remains is the clock tree, the flop clock pins
#     (sequential internal) and leakage. Macro power is reported but excluded from the floor (SRAM energy comes from pCACTI).
#  D (reference, ENERGY_PLAN D4): OpenSTA default activities, to reconcile the earlier 205 mW vs 4.7 mW discrepancy.
# Usage: sbatch [-p <partition>] floor_job.sh <design> ...   (design = layout name as in energy_map.tsv column 3; one partition per job, the
# cluster refuses partition lists; user Oct 28: genoa, next-mi210, qc-pvc, qc-mi250, fs-mi300a, fs-mi300x, next-pvc allowed)
T=${CLOUD_ROOT}; F=$T/pnr_fpnew/flow; SIF=$HOME/workspace/GPU_and_PNM/containers/orfs_v3.0-4367-g79b6a48ab.sif
O=$T/floors; STDLIB='/OpenROAD-flow-scripts/flow/platforms/asap7/lib/NLDM/asap7sc7p5t_*_RVT_TT_nldm_2*.lib*'
# VDDONLY=1: standard-cell libs without their VSS internal/leakage power groups (libs_vddonly/, made by strip_vss.py there).
# ASAP7 lists every internal and leakage power group once per rail (VDD and VSS) and OpenSTA sums both; this variant counts VDD only.
if [ "${VDDONLY:-0}" = 1 ]; then O=$T/floors_vddonly; STDLIB="$T/libs_vddonly/asap7sc7p5t_*_RVT_TT_nldm_2*.lib"; fi
mkdir -p $O
[ $# -ge 1 ] || { echo "usage: floor_job.sh <design> ..."; exit 1; }
for n in "$@"; do
  d=vortex_${n}_fpnew; R=/OpenROAD-flow-scripts/flow/results/asap7/$d/base
  # sign-off period and odb from signoff.tsv (default 2000 ps, 6_final.odb)
  [ -f $T/signoff.tsv ] && [ -f $T/signoff_check.awk ] && awk -F'\t' -f $T/signoff_check.awk $T/signoff.tsv || { echo "FAILED $n: $T/signoff.tsv missing or malformed (tabs, 3 fields, unique layouts)"; continue; }
  P=2000; ODB=6_final.odb; L=$(awk -F'\t' -v n="$n" '$1==n {print $2" "$3}' $T/signoff.tsv); [ -n "$L" ] && read P ODB <<< "$L"
  [ -f $F/results/asap7/$d/base/$ODB ] && [ -f $F/results/asap7/$d/base/6_final.spef ] || { echo "FAILED $n: no $ODB or spef"; continue; }
  cat > $O/$n.tcl <<EOF
suppress_message STA 1212
foreach l [glob $STDLIB] { read_liberty \$l }
foreach l [glob /OpenROAD-flow-scripts/flow/platforms/asap7/lib/NLDM/fakeram7_*_be.lib] { read_liberty \$l }
read_db $R/$ODB
read_spef $R/6_final.spef
create_clock -name clk -period $P [get_ports clk]
set_propagated_clock [get_clocks clk]
puts "INFO $n period=$P odb=$ODB insts=[llength [get_cells *]] regs=[llength [all_registers]]"
puts "=== D $n (default activities)"
report_power -digits 6
set_power_activity -global -activity 0
set_power_activity -input -activity 0
puts "=== F $n (floor: non-clock activity 0)"
report_power -digits 6
EOF
  ( singularity exec --bind $F:/OpenROAD-flow-scripts/flow --bind $T:$T $SIF bash -c "source /OpenROAD-flow-scripts/env.sh >/dev/null && openroad -no_init -exit $O/$n.tcl" > $O/$n.log 2>&1
    grep -qE "^=== F" $O/$n.log && echo "DONE $n" || echo "FAILED $n: $(grep -m2 -E 'Error|ERROR' $O/$n.log)" ) &
done
wait; echo FLOOR_DONE
