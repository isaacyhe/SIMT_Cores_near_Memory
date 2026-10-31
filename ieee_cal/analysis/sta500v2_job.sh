#!/bin/bash
#SBATCH -p genoa
#SBATCH -N 1
#SBATCH -t 06:00:00
#SBATCH -o ${CLOUD_ROOT}/logs/sta500v2_%j.out
# 500 MHz evaluation of every routed design (routed odb + spef, TT libs + FakeRAM libs), two I/O models:
#  A: as routed SDC with period 2000 ps (external side on an ideal clock).
#  B: external side on a virtual clock 'vclk' (2000 ps) whose latency = mean propagated clock latency at the design's register
#     clock pins, i.e. the receiver/driver outside the core sits on a clock tree like the core's. Same 100 ps I/O delays; I/O hold
#     paths stay excluded. Reports overall setup/hold, register-to-register setup, and I/O-only setup in both models.
# Usage: sbatch sta500v2_job.sh [design ...]   (default: every design with 6_final.odb + spef)
T=${CLOUD_ROOT}; F=$T/pnr_fpnew/flow; SIF=$HOME/workspace/GPU_and_PNM/containers/orfs_v3.0-4367-g79b6a48ab.sif
O=$T/sta500v2; mkdir -p $O
designs="$*"; [ -n "$designs" ] || designs=$(for R in $F/results/asap7/vortex_*_fpnew/base; do [ -f $R/6_final.odb ] && [ -f $R/6_final.spef ] && basename $(dirname $R) | sed 's/^vortex_//;s/_fpnew$//'; done)
for n in $designs; do
  d=vortex_${n}_fpnew; R=/OpenROAD-flow-scripts/flow/results/asap7/$d/base
  cat > $O/$n.tcl <<EOF
suppress_message STA 1212
foreach l [glob /OpenROAD-flow-scripts/flow/platforms/asap7/lib/NLDM/asap7sc7p5t_*_RVT_TT_nldm_2*.lib*] { read_liberty \$l }
foreach l [glob /OpenROAD-flow-scripts/flow/platforms/asap7/lib/NLDM/fakeram7_*_be.lib] { read_liberty \$l }
read_db $R/6_final.odb
read_spef $R/6_final.spef
set ins [delete_from_list [all_inputs] [get_ports clk]]
proc io_ws {} { set w 1e9; foreach p [get_ports -quiet [all_outputs]] { set s [get_property \$p slack_max]; if {\$s ne "" && \$s ne "INF" && \$s < \$w} {set w \$s} }; return \$w }
proc r2r_ws {} { set w 1e9; foreach p [all_registers -data_pins] { set s [get_property \$p slack_max]; if {\$s ne "" && \$s ne "INF" && \$s < \$w} {set w \$s} }; return \$w }
# --- model A: as routed, period 2000
create_clock -name clk -period 2000 [get_ports clk]
set_propagated_clock [get_clocks clk]
set_input_delay 100 -clock clk \$ins
set_output_delay 100 -clock clk [all_outputs]
set_false_path -hold -from \$ins
set_false_path -hold -to [all_outputs]
puts "A $n setup_ws=[sta::worst_slack -max] hold_ws=[sta::worst_slack -min] r2r_setup_ws=[r2r_ws] io_out_setup_ws=[io_ws]"
# --- model B: external side on a virtual clock with the core's mean clock latency
set sum 0.0; set k 0
foreach p [all_registers -clock_pins] { set a [get_property \$p arrival_max_rise]; if {\$a ne "" && \$a ne "INF"} { set sum [expr {\$sum + \$a}]; incr k } }
set lat [expr {\$k > 0 ? \$sum / \$k : 0.0}]
create_clock -name vclk -period 2000
set_clock_latency \$lat [get_clocks vclk]
set_input_delay 100 -clock vclk \$ins
set_output_delay 100 -clock vclk [all_outputs]
unset_input_delay -clock clk \$ins
unset_output_delay -clock clk [all_outputs]
set_false_path -hold -from \$ins
set_false_path -hold -to [all_outputs]
puts "B $n latency=[format %.1f \$lat] regs=\$k setup_ws=[sta::worst_slack -max] hold_ws=[sta::worst_slack -min] r2r_setup_ws=[r2r_ws] io_out_setup_ws=[io_ws]"
EOF
  ( singularity exec --bind $F:/OpenROAD-flow-scripts/flow --bind $T:$T $SIF bash -c "source /OpenROAD-flow-scripts/env.sh >/dev/null && openroad -no_init -exit $O/$n.tcl" > $O/$n.log 2>&1; grep -hE "^(A|B) " $O/$n.log || echo "FAILED $n: $(grep -m2 -E 'Error|ERROR' $O/$n.log)" ) &
done
wait; echo STA500V2_DONE
