#!/bin/bash
#SBATCH -N 1
#SBATCH -c 8
#SBATCH -t 12:00:00
#SBATCH -o ${CLOUD_ROOT}/logs/calib_power_%j.out
# Core-switching calibration, power side (Oct 31). One OpenROAD session per window, same setup as core_dyn_job.sh (VDD-rail TT
# libs, FakeRAM libs, routed odb + spef from signoff.tsv, propagated clock at the sign-off period, primary inputs at activity 0):
#   ZERO    every flop group at activity 0 (reference, as in core_dyn_job.sh);
#   INTERIM the window's per-group activities from the RTL window counters (calib_window_act.py line), as core_dyn_job.sh;
#   TRUTH   read_vcd of the gate-level window (scope TOP/rtlsim_shim/vortex/gl), last, so every net in the VCD is annotated.
# Calibration compares (Seq + Comb + Clock)(TRUTH) - ZERO with (Seq + Comb + Clock)(INTERIM) - ZERO; Macro rows are excluded.
# Usage: sbatch -p <partition> calib_power_job.sh <layout> <act_file> <tag>=<vcd.gz> ...   (act_file: lines from calib_window_act.py)
set -u
T=${CLOUD_ROOT}; F=$T/pnr_fpnew/flow; SIF=$HOME/workspace/GPU_and_PNM/containers/orfs_v3.0-4367-g79b6a48ab.sif
# one output dir per (layout, config, r): windows of the two ratios often share a tag
n=$1; ACT=$2; shift 2; O=$T/calib/power/$(basename $ACT .act.tsv); mkdir -p $O; d=vortex_${n}_fpnew; R=/OpenROAD-flow-scripts/flow/results/asap7/$d/base
[ -f $T/signoff.tsv ] && [ -f $T/signoff_check.awk ] && awk -F'\t' -f $T/signoff_check.awk $T/signoff.tsv || { echo "signoff.tsv missing or malformed"; exit 1; }
L=$(awk -F'\t' -v n="$n" '$1==n {print $2" "$3}' $T/signoff.tsv); if [ -n "$L" ]; then read P ODB <<< "$L"; else P=2000; ODB=6_final.odb; fi
LOCAL=/tmp/calpow_${SLURM_JOB_ID:-manual$$}; mkdir -p $LOCAL
for spec in "$@"; do
  tag=${spec%%=*}; vcd=${spec#*=}
  line=$(awk -F'\t' -v t="$tag" '$3==t' $ACT); [ -n "$line" ] || { echo "$tag: no act line in $ACT"; continue; }
  [ -s $vcd ] || { echo "$tag: no $vcd"; continue; }
  gzip -dc $vcd > $LOCAL/$tag.vcd || { echo "$tag: gunzip failed"; continue; }
  echo "$line" > $LOCAL/$tag.act
  cat > $O/$tag.tcl <<EOT
suppress_message STA 1212
foreach l [glob $T/libs_vddonly/asap7sc7p5t_*_RVT_TT_nldm_2*.lib] { read_liberty \$l }
foreach l [glob /OpenROAD-flow-scripts/flow/platforms/asap7/lib/NLDM/fakeram7_*_be.lib] { read_liberty \$l }
read_db $R/$ODB
read_spef $R/6_final.spef
create_clock -name clk -period $P [get_ports clk]
set_propagated_clock [get_clocks clk]
puts "INFO $n period=$P odb=$ODB window=$tag"
set ins [delete_from_list [all_inputs] [get_ports clk]]
set_power_activity -input_ports \$ins -activity 0
array set G {}
set fh [open $T/flopgroups/$n.tsv r]; set miss 0
while {[gets \$fh line] >= 0} {
  lassign [split \$line "\t"] g inst
  set c [sta::find_instance \$inst]
  if {\$c eq "NULL" || \$c eq ""} { incr miss; continue }
  foreach p [get_pins -of_objects \$c -filter "direction == output"] { lappend G(\$g) \$p }
}
close \$fh
puts "GROUPS [array size G] missing_instances \$miss"
foreach g [array names G] { set_power_activity -pins \$G(\$g) -activity 0 -duty 0.5 }
puts "=== RUN ZERO"
report_power -digits 6
set f [split [string trim [read [open $LOCAL/$tag.act]]] "\t"]
foreach kv [lrange \$f 4 end] { lassign [split \$kv =] g a; if {[info exists G(\$g)]} { set_power_activity -pins \$G(\$g) -activity \$a -duty 0.5 } else { puts "NOGROUP \$g" } }
puts "=== RUN INTERIM [lrange \$f 0 3]"
report_power -digits 6
read_vcd -scope TOP/rtlsim_shim/vortex/gl $LOCAL/$tag.vcd
puts "=== RUN TRUTH [lrange \$f 0 3]"
report_power -digits 6
puts CALPOW_DONE
EOT
  singularity exec --bind $F:/OpenROAD-flow-scripts/flow --bind $T:$T --bind $LOCAL:$LOCAL $SIF bash -c "source /OpenROAD-flow-scripts/env.sh >/dev/null && openroad -no_init -exit $O/$tag.tcl" > $O/$tag.log 2>&1
  rm -f $LOCAL/$tag.vcd
  echo "$tag: $(grep -c '^=== RUN' $O/$tag.log) reports, $(grep -c CALPOW_DONE $O/$tag.log) done, $(grep -m2 -E 'Error|ERROR|Warning: .*vcd' $O/$tag.log | tr '\n' ' ')"
done
rm -rf $LOCAL; echo CALPOW_ALL_DONE
