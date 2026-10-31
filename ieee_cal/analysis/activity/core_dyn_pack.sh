#!/bin/bash
#SBATCH -N 1
#SBATCH -c 32
#SBATCH -t 24:00:00
#SBATCH -o ${CLOUD_ROOT}/logs/coredyn_pack_%j.out
# Runs core_dyn_job.sh for several layouts concurrently on one node (period from signoff.tsv, as floor_job.sh).
# Usage: sbatch -p <partition> core_dyn_pack.sh <layout> ...
T=${CLOUD_ROOT}
[ -f $T/signoff.tsv ] && [ -f $T/signoff_check.awk ] && awk -F'\t' -f $T/signoff_check.awk $T/signoff.tsv || { echo "$T/signoff.tsv missing or malformed (tabs, 3 fields, unique layouts)"; exit 1; }
for n in "$@"; do P=2000; ODB=6_final.odb; L=$(awk -F'\t' -v n="$n" '$1==n {print $2" "$3}' $T/signoff.tsv); [ -n "$L" ] && read P ODB <<< "$L"; ( echo "$n: $(bash $T/core_dyn_job.sh $n $P | tr '\n' ' ')" ) & done
wait; echo PACK_DONE
