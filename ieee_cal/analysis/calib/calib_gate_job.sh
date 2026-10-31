#!/bin/bash
#SBATCH -N 1
#SBATCH --exclusive
#SBATCH --mem=0
#SBATCH -t 24:00:00
#SBATCH -o ${CLOUD_ROOT}/logs/calib_gate_%j.out
# Core-switching calibration, gate-level side (Oct 31). One routed layout and one energy config at one ratio:
#  1. unpack the wave tree (wave1/tree.tar, c2c4ce3 + prebuilt libraries) node-locally and overlay sim/gatesim_fpnew;
#  2. in the simulation container, build the gate librtlsim.so from calib/gl/<layout>/{Vortex_gl.v,gen_cells.v} with CONFIGS =
#     the energy rows' rtlsim_configs, and the rtlsim runtime driver against it (built by hand: runtime/rtlsim's Makefile would
#     rebuild the RTL librtlsim.so into the same directory);
#  3. run each benchmark the way run_single_rtlsim.sh runs an energy row (same env: VX_CTR_FILE, VX_DRAM_CMDSTATS, profiling on,
#     PoCL cache off; soft-math configs from benchmarks_modified with POCL_EXTRA_BUILD_FLAGS), optionally with a trace window
#     (VX_TRACE_START/VX_TRACE_STOP timestamps, VCD dumped only inside, VX_EARLY_EXIT ends the run after it).
# Outputs to calib/out/<layout>_<cfg>_<r>/<bench>[_<start>_<stop>].{log,ctr,dram.tgz,vcd.gz}.
# Usage: sbatch -p <partition> calib_gate_job.sh <gate|rtl> <layout> <energy_config> <ratio> <threads> <bench>:<opts>[:<start>:<stop>] ...
#   gate: gatesim_fpnew on the routed netlist (VCD in the window); rtl: sim/rtlsim_cal, the energy RTL build with the same harness
#   (window counter snapshots; the gate netlist has no counter hardware), so both see the same cycles.
#        (opts with __ for spaces, as in the job files; no window = full run, no VCD)
set -u
T=${CLOUD_ROOT}; W=$T/wave1; C=$T/calib; SIF=$HOME/workspace/GPU_and_PNM/containers/pnm-simt-artifact-v3.sif
MODE=$1; LAY=$2; CFG=$3; R=$4; NT=$5; shift 5
case $MODE in gate|rtl) ;; *) echo "REFUSED: mode $MODE"; exit 1 ;; esac
GL=$C/gl/$LAY; OUT=$C/out/${LAY}_${CFG}_${R}/$MODE; mkdir -p $OUT
[ $MODE = rtl ] || { [ -s $GL/Vortex_gl.v ] && [ -s $GL/gen_cells.v ]; } || { echo "REFUSED: no netlist/cell models in $GL"; exit 1; }
[ -d $C/src/gatesim_fpnew ] && [ -d $C/src/rtlsim_cal ] || { echo "REFUSED: no $C/src/{gatesim_fpnew,rtlsim_cal}"; exit 1; }
mkdir -p $GL
OV=$(sed -n 's/^[[:space:]]*VX_CONFIG_OVERRIDE[[:space:]]*=[[:space:]]*//p' $W/tree/GPU_and_PNM/eval_perf_swemu/configs/$CFG/config.mk | tail -1)
CF=$(sed -n 's/^[[:space:]]*CFLAGS[[:space:]]*+=[[:space:]]*//p' $W/tree/GPU_and_PNM/eval_perf_swemu/configs/$CFG/config.mk | tr '\n' ' ')
UM=$(grep -qE '^[[:space:]]*USE_MODIFIED_BENCHMARKS[[:space:]]*=[[:space:]]*1' $W/tree/GPU_and_PNM/eval_perf_swemu/configs/$CFG/config.mk && echo 1 || echo 0)
CONFIGS="-DMEM_CLOCK_RATIO=$R $OV -DVERILATOR_RESET_VALUE=0"
LOCAL=/tmp/calib_${SLURM_JOB_ID:-manual$$}; mkdir -p $LOCAL/tmp
tar -xf $W/tree.tar -C $LOCAL || { echo "tree unpack failed"; exit 1; }
cp -r $C/src/gatesim_fpnew $C/src/rtlsim_cal $LOCAL/GPU_and_PNM/vortex/sim/
touch -c $LOCAL/GPU_and_PNM/vortex/kernel/libvortex.a $LOCAL/GPU_and_PNM/vortex/kernel/softdiv/libvortex.a $LOCAL/GPU_and_PNM/vortex/runtime/libvortex.so
echo "start $(date -Is) $(hostname) layout=$LAY cfg=$CFG r=$R CONFIGS=[$CONFIGS] CFLAGS=[$CF] modified=$UM tree=$(git -C $LOCAL/GPU_and_PNM log --oneline -1 | cut -c1-12)"
if [ $MODE = gate ]; then KEY="gate net=$(md5sum < $GL/Vortex_gl.v | cut -c1-12) cells=$(md5sum < $GL/gen_cells.v | cut -c1-12) harness=$(cat $C/src/gatesim_fpnew/* | md5sum | cut -c1-12) configs=$CONFIGS"
else KEY="rtl harness=$(cat $C/src/rtlsim_cal/* | md5sum | cut -c1-12) tree=$(git -C $LOCAL/GPU_and_PNM rev-parse --short=12 HEAD) configs=$CONFIGS"; fi
echo "$KEY"   # the cached gate library in $OUT/rt is reused only when this key matches
singularity exec --pid --cleanenv \
  --bind $LOCAL/GPU_and_PNM:/home/he/workspace/GPU_and_PNM \
  --bind $W/toolchain:/home/he/workspace/GPU_and_PNM/toolchain:ro \
  --bind $W/shim/bc:/usr/bin/bc --bind $LOCAL/tmp:/tmp --bind $GL:/gl:ro --bind $OUT:/out \
  $SIF bash -c '
    set -u; export HOME=/tmp/home; mkdir -p $HOME
    V=/home/he/workspace/GPU_and_PNM/vortex; RT=$V/runtime_gcal; mkdir -p $RT
    export VORTEX_HOME=$V MARCH=rv32imf MABI=ilp32f   # as run_single_rtlsim.sh (the test Makefiles fall back to the artifact path otherwise)
    verilator --version
    if [ -s /out/rt/librtlsim.so ] && [ "$(cat /out/rt/KEY 2>/dev/null)" = "'"$KEY"'" ]; then cp /out/rt/* $RT/; echo "gate lib reused (key match), md5 $(md5sum < $RT/librtlsim.so | cut -c1-12)"; else
    t0=$(date +%s)
    if [ '"$MODE"' = gate ]; then make -C $V/sim/gatesim_fpnew lib DESTDIR=$RT VORTEX_HOME=$V GL_DIR=/gl CONFIGS="'"$CONFIGS"'" PERF=1 THREADS='"$NT"' > /out/build.log 2>&1
    else make -C $V/sim/rtlsim_cal DESTDIR=$RT VORTEX_HOME=$V CONFIGS="'"$CONFIGS"'" PERF=1 THREADS='"$NT"' $RT/librtlsim.so > /out/build.log 2>&1; fi || { echo "LIB BUILD FAILED"; tail -20 /out/build.log; exit 1; }
    echo "'"$MODE"' lib built in $(( $(date +%s) - t0 )) s, md5 $(md5sum < $RT/librtlsim.so | cut -c1-12)"
    g++ -std=c++17 -fPIC -O2 -DNDEBUG -DXLEN_32 '"$CONFIGS"' -I$V/runtime/include -I$V/hw -I$V/sim/rtlsim -I$V/sim/common -I$V/runtime/common \
        $V/runtime/rtlsim/vortex.cpp -shared -pthread -L$RT -lrtlsim -Wl,-rpath,$RT -o $RT/libvortex-rtlsim.so >> /out/build.log 2>&1 || { echo "DRIVER BUILD FAILED"; exit 1; }
    cp $V/runtime/libvortex.so $RT/
    mkdir -p /out/rt; cp $RT/librtlsim.so $RT/libvortex-rtlsim.so $RT/libvortex.so /out/rt/; echo "'"$KEY"'" > /out/rt/KEY; fi
    for spec in '"$*"'; do
      IFS=: read -r B O S E <<< "$spec"; O=${O//__/ }; tag=$B${S:+_${S}_${E}}
      if [ '"$UM"' = 1 ]; then BD=/home/he/workspace/GPU_and_PNM/eval_perf_swemu/benchmarks_modified/$B; export POCL_EXTRA_BUILD_FLAGS="'"$CF"'"; else BD=$V/tests/opencl/$B; unset POCL_EXTRA_BUILD_FLAGS; fi
      cd $BD || { echo "$tag: no $BD"; continue; }
      make MARCH=rv32imf MABI=ilp32f TOOLDIR=/home/he/workspace/GPU_and_PNM/toolchain >/dev/null 2>&1
      rm -rf /tmp/run_$tag; mkdir -p /tmp/run_$tag; rm -f trace.vcd
      export VX_CTR_FILE=/tmp/run_$tag/vx.ctr VX_DRAM_CMDSTATS=/tmp/run_$tag/dramcmd VORTEX_PROFILING=1 POCL_KERNEL_CACHE=0
      unset VX_TRACE_START VX_TRACE_STOP VX_EARLY_EXIT; [ -n "$S" ] && export VX_TRACE_START=$S VX_TRACE_STOP=$E VX_EARLY_EXIT=1
      t1=$(date +%s)
      make run-rtlsim MARCH=rv32imf MABI=ilp32f PERF=1 TOOLDIR=/home/he/workspace/GPU_and_PNM/toolchain VORTEX_RT_PATH=$RT ${POCL_EXTRA_BUILD_FLAGS:+CONFIGS="$POCL_EXTRA_BUILD_FLAGS"} OPTS="$O" > /out/$tag.log 2>&1; rc=$?
      echo "$tag rc=$rc $(( $(date +%s) - t1 )) s: $(grep -m1 -oE "cycles=[0-9]+|PERF: .*cycles=[0-9]+" /out/$tag.log | tail -1)"
      cp /tmp/run_$tag/vx.ctr /out/$tag.ctr 2>/dev/null; tar -czf /out/$tag.dram.tgz -C /tmp/run_$tag . 2>/dev/null
      [ -f trace.vcd ] && gzip -c trace.vcd > /out/$tag.vcd.gz && rm -f trace.vcd
    done'
rc=$?; echo "done $(date -Is) rc=$rc"; rm -rf $LOCAL; exit $rc   # non-zero on a failed build, so afterok-chained comparisons do not start
