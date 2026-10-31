#!/bin/bash
#SBATCH -N 1
#SBATCH -c 8
#SBATCH -t 24:00:00
#SBATCH -o ${CLOUD_ROOT}/logs/coredyn_%j.out
# Interim (uncalibrated) per-run core switching power (Oct 29): routed odb + spef, VDD-rail TT libs, propagated clock at the
# sign-off period; every flop output set to its group's per-run activity (act/<layout>.act.tsv from core_dyn_prep.py, groups from
# flopgroups/<layout>.tsv), primary inputs at activity 0, combinational activity propagated by OpenSTA; one report_power per run.
# Usage: sbatch [-p partition] core_dyn_job.sh <layout> <period_ps>
T=${CLOUD_ROOT}; F=$T/pnr_fpnew/flow; SIF=$HOME/workspace/GPU_and_PNM/containers/orfs_v3.0-4367-g79b6a48ab.sif
n=$1; P=$2; O=$T/coredyn; mkdir -p $O; d=vortex_${n}_fpnew; R=/OpenROAD-flow-scripts/flow/results/asap7/$d/base
# odb and period from signoff.tsv (default 6_final.odb, 2000 ps); the period passed in must match it
[ -f $T/signoff.tsv ] && [ -f $T/signoff_check.awk ] && awk -F'\t' -f $T/signoff_check.awk $T/signoff.tsv || { echo "$T/signoff.tsv missing or malformed"; exit 1; }
L=$(awk -F'\t' -v n="$n" '$1==n {print $2" "$3}' $T/signoff.tsv)
if [ -n "$L" ]; then read PS ODB <<< "$L"; else PS=2000; ODB=6_final.odb; fi
[ "$PS" = "$P" ] || { echo "period $P != signoff.tsv $PS for $n"; exit 1; }
cat > $O/$n.tcl <<EOF
suppress_message STA 1212
foreach l [glob $T/libs_vddonly/asap7sc7p5t_*_RVT_TT_nldm_2*.lib] { read_liberty \$l }
foreach l [glob /OpenROAD-flow-scripts/flow/platforms/asap7/lib/NLDM/fakeram7_*_be.lib] { read_liberty \$l }
read_db $R/$ODB
read_spef $R/6_final.spef
create_clock -name clk -period $P [get_ports clk]
puts "INFO $n period=$P odb=$ODB"
set_propagated_clock [get_clocks clk]
set ins [delete_from_list [all_inputs] [get_ports clk]]
set_power_activity -input_ports \$ins -activity 0
# group -> output pins of its flops (sta::find_instance takes literal names: no glob on the [ ] in hierarchical names)
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
foreach g [lsort [array names G]] { puts "GROUP \$g [llength \$G(\$g)]" }
# reference: every flop group at activity 0 (core switching = run total - ZERO total; clock, macro and leakage rows cancel)
foreach g [array names G] { set_power_activity -pins \$G(\$g) -activity 0 -duty 0.5 }
puts "=== RUN ZERO"
report_power -digits 6
set fh [open $T/coredyn/act/$n.act.tsv r]
while {[gets \$fh line] >= 0} {
  set f [split \$line "\t"]; lassign \$f cfg r bench busy
  foreach g [array names G] { set_power_activity -pins \$G(\$g) -activity 0 -duty 0.5 }
  foreach kv [lrange \$f 4 end] { lassign [split \$kv =] g a; if {[info exists G(\$g)]} { set_power_activity -pins \$G(\$g) -activity \$a -duty 0.5 } else { puts "NOGROUP \$g" } }
  puts "=== RUN \$cfg \$r \$bench \$busy"
  report_power -digits 6
}
close \$fh
puts COREDYN_DONE
EOF
singularity exec --bind $F:/OpenROAD-flow-scripts/flow --bind $T:$T $SIF bash -c "source /OpenROAD-flow-scripts/env.sh >/dev/null && openroad -no_init -exit $O/$n.tcl" > $O/$n.log 2>&1
grep -c "^=== RUN" $O/$n.log; tail -2 $O/$n.log
