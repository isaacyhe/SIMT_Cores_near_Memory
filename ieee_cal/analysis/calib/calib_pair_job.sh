#!/bin/bash
#SBATCH -N 1
#SBATCH -c 8
#SBATCH -t 12:00:00
#SBATCH -o ${CLOUD_ROOT}/logs/calib_pair_%j.out
# Calibration, one (layout, config, r) after its gate and rtl calib_gate_job.sh runs (Oct 31): interim window activities from the RTL
# window counters (calib_window_act.py, same activities() as production, run from the copy of ieee_cal/analysis in calib/py), then
# calib_power_job.sh for every window that has a gate VCD. Submitted with --dependency=afterok:<gate>:<rtl>.
# Usage: sbatch -p <partition> --dependency=afterok:<g>:<r> calib_pair_job.sh <layout> <config> <r>
set -u
T=${CLOUD_ROOT}; C=$T/calib; LAY=$1; CFG=$2; R=$3; O=$C/out/${LAY}_${CFG}_${R}
ACT=$C/act/${LAY}_${CFG}_${R}.act.tsv; mkdir -p $C/act; : > $ACT.tmp; specs=()
for ctr in $O/rtl/*_*_*.ctr; do
  tag=$(basename $ctr .ctr); vcd=$O/gate/$tag.vcd.gz
  [ -s $vcd ] || { echo "$tag: no gate VCD"; continue; }
  python3 $C/py/calib/calib_window_act.py $LAY $CFG $R $tag $ctr >> $ACT.tmp || { echo "$tag: act FAILED"; continue; }
  specs+=("$tag=$vcd")
done
mv $ACT.tmp $ACT; echo "$(wc -l < $ACT) windows with activities"
bash $T/calib_power_job.sh $LAY $ACT "${specs[@]}"
