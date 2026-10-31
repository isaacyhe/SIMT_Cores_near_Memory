#!/bin/bash
#SBATCH -p genoa
#SBATCH -N 1
#SBATCH -t 24:00:00
#SBATCH -o ${CLOUD_ROOT}/logs/pnr_fpnew_%x_%j.out
# Route FPnew designs side by side on one exclusive node. Args: "design:cores" (design = nickname without vortex_/_fpnew).
# Every route is a child of this batch script (lives as long as the job). After a successful finish the results dir is
# pruned to what power/energy needs (6_final.odb/.spef/.sdc/.v, 1_2_yosys.v); logs and reports are kept in full.
T=${CLOUD_ROOT}; F=$T/pnr_fpnew/flow; SIF=$HOME/workspace/GPU_and_PNM/containers/orfs_v3.0-4367-g79b6a48ab.sif
export QT_QPA_PLATFORM=offscreen; mkdir -p $T/logs
quota_ok() { local used=$(lfs quota -p ${CLOUD_QUOTA_PROJECT} ${CLOUD_FS} | awk 'NR==3{print $2}'); local lim=$(lfs quota -p ${CLOUD_QUOTA_PROJECT} ${CLOUD_FS} | awk 'NR==3{print $4}'); [ $(( (lim-used)/1024/1024 )) -gt 100 ]; }
echo "start $(date -Is) on $(hostname): $*"
for spec in "$@"; do
  D=${spec%%:*}; C=${spec##*:}; [ "$C" = "$D" ] && C=4
  ( quota_ok || { echo "SKIP $D: team quota < 100 GB free"; exit 0; }
    singularity exec --bind $F:/OpenROAD-flow-scripts/flow $SIF bash -c \
      "source /OpenROAD-flow-scripts/env.sh && cd /OpenROAD-flow-scripts/flow && make DESIGN_CONFIG=./designs/asap7/vortex_${D}_fpnew/config.mk NUM_CORES=$C finish" \
      > $T/logs/pnr_fpnew_${D}_${SLURM_JOB_ID}.out 2>&1; rc=$?
    echo "end $(date -Is) $D rc=$rc"
    R=$F/results/asap7/vortex_${D}_fpnew/base
    if [ $rc -eq 0 ] && [ -f $F/logs/asap7/vortex_${D}_fpnew/base/6_report.json ]; then
      find $R -maxdepth 1 -type f ! -name "6_final.odb" ! -name "6_final.spef" ! -name "6_final.sdc" ! -name "6_final.v" ! -name "1_2_yosys.v" ! -name "*.txt" ! -name "*.json" ! -name "*.tcl" -delete
      echo "pruned $D: $(du -sh $R | cut -f1)"
    fi ) &
done
wait; echo PACK_DONE
