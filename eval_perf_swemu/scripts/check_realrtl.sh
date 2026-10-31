#!/bin/bash
# Real-RTL guard for CAL energy/performance runs (sourced by run_single_rtlsim*.sh and run_parallel_rtlsim*.sh).
# Active when VX_REALRTL=1 or VX_CMDSTATS_ON is set. Simulation must build the same ALU/FPU RTL as the routed layouts:
# FPnew FPU (T-Head div/sqrt) and RTL integer mul/div, i.e. -DFPU_FPNEW -DDPI_DISABLE, and nothing that switches back to
# DPI models or the PULP divider.
realrtl_required() { [ "${VX_REALRTL:-0}" = "1" ] || [ "${VX_CMDSTATS_ON:-0}" = "1" ]; }

# sim_lib_md5s <vortex_dir> -> "librtlsim=<md5_12> libvortex=<md5_12>" of the runtime libraries a run loads (empty md5 = missing)
sim_lib_md5s() {
    echo "librtlsim=$(md5sum < "$1/runtime/librtlsim.so" 2>/dev/null | cut -c1-12) libvortex=$(md5sum < "$1/runtime/libvortex-rtlsim.so" 2>/dev/null | cut -c1-12)"
}
# runtime_lock_or_die <vortex_dir>: builders that write runtime/librtlsim.so must not run while a campaign uses it
# (shared lock: such builders may run side by side; the campaign runner takes it exclusively)
runtime_lock_or_die() {
    exec 8>"$1/runtime/.rtlsim_campaign.lock"
    flock -sn 8 || { echo "ERROR: an rtlsim campaign holds $1/runtime/.rtlsim_campaign.lock; build in another tree or wait"; exit 1; }
}

# Clean environment for CAL energy (allowlist, not a blocklist: no inherited variable may change what make, Verilator,
# g++, clang/PoCL, the dynamic loader, git or bash do). The launcher and the checker re-execute themselves under env -i
# with only these; the runner and run_single refuse in real-RTL mode if anything else is exported or PATH differs.
REALRTL_PATH="/usr/bin:/bin"
REALRTL_LIB_MD5=da3103230861a536ad5d16cafff03ee8   # the validated libramulator.so (VxCmdStats, VxPhysRefresh, run-only ticks)
REALRTL_ENV_KEEP="HOME USER LOGNAME LANG TERM PATH PWD OLDPWD SHLVL _ TMPDIR VX_CLEAN_ENV VX_REALRTL VX_CMDSTATS_ON RESULTS_TAG
 VX_RUN_TIMEOUT CAMPAIGN_BUILD_ID SKIP_RTLSIM_BUILD FORCE_RERUN ENERGY_BUILD_ID GIT_CONFIG_NOSYSTEM GIT_CONFIG_GLOBAL PYTHONNOUSERSITE"
realrtl_env_dirty() {
    local v
    while IFS= read -r -d '' v; do v="${v%%=*}"; [[ " $(echo $REALRTL_ENV_KEEP) " == *" $v "* ]] || echo "$v"; done < <(/usr/bin/env -0)
    [ "$PATH" = "$REALRTL_PATH" ] || echo "PATH($PATH)"
    [ "${GIT_CONFIG_NOSYSTEM:-}" = "1" ] && [ "${GIT_CONFIG_GLOBAL:-}" = "/dev/null" ] && [ "${PYTHONNOUSERSITE:-}" = "1" ] || echo "GIT_CONFIG_NOSYSTEM/GIT_CONFIG_GLOBAL/PYTHONNOUSERSITE not set"
    local f; f=$(compgen -A function | grep -vxE "$REALRTL_OWN_FUNCS"); [ -z "$f" ] || echo "unexpected shell functions: $(echo $f)"   # BASH_FUNC_* / BASH_ENV
    return 0
}
# realrtl_reexec_clean <script> <args...>: re-execute under the clean environment (once)
realrtl_reexec_clean() {
    [ "${VX_CLEAN_ENV:-}" = "1" ] && return 0
    local -a keep=(HOME="$HOME" USER="${USER:-}" LOGNAME="${LOGNAME:-}" LANG="${LANG:-C.UTF-8}" TERM="${TERM:-dumb}" PATH="$REALRTL_PATH" VX_CLEAN_ENV=1
                   GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null PYTHONNOUSERSITE=1)   # no ~/.gitconfig, /etc/gitconfig, user site-packages
    local v
    for v in FORCE_RERUN VX_RUN_TIMEOUT ENERGY_BUILD_ID; do [ -n "${!v:-}" ] && keep+=("$v=${!v}"); done
    exec /usr/bin/env -i "${keep[@]}" /bin/bash "$@"
}

# check_realrtl_configs "<RTLSIM_CONFIGS>" -> 0 ok, 1 mismatch (reason on stdout)
check_realrtl_configs() {
    local cfg=" $1 " t
    for t in -DFPU_FPNEW -DDPI_DISABLE; do
        [[ "$cfg" == *" $t "* ]] || { echo "missing $t"; return 1; }
    done
    for t in -DFPU_DPI -DFPU_DSP -DIMUL_DPI -DIDIV_DPI -DFPNEW_PULP_DIVSQRT -DSV_DPI_FPU; do
        [[ "$cfg" == *" $t "* || "$cfg" == *" $t="* ]] && { echo "forbidden $t"; return 1; }
    done
    return 0
}

# check_realrtl_lib <path/to/librtlsim.so> [rtlsim configs] -> 0 ok, 1 mismatch. Sim-only message strings show what was compiled in:
# the T-Head guard (FPnew with its div/sqrt unit), the FPnew FDIV/FSQRT guard (FPnew with DIVSQRT DISABLED, -DFPU_DIVSQRT_DISABLE) and
# the IDIV guard (-DIDIV_DISABLE). Each must be present exactly when the configs ask for it (Oct 28, soft-math configs).
check_realrtl_lib() {
    local lib="$1" c=" $(echo ${2:-}) " th=0 fd=0 id=0
    [ -f "$lib" ] || { echo "library not found: $lib"; return 1; }
    grep -aq "fpnew_divsqrt_th_32: native latency exceeded LPAD" "$lib" && th=1
    grep -aq "VX_fpu_fpnew: FDIV/FSQRT issued with FPU_DIVSQRT_DISABLE" "$lib" && fd=1
    grep -aq "VX_alu_muldiv: integer div/rem issued with IDIV_DISABLE" "$lib" && id=1
    if [[ "$c" == *" -DFPU_DIVSQRT_DISABLE "* ]]; then
        [ "$fd" = 1 ] && [ "$th" = 0 ] || { echo "librtlsim.so: FPnew without div/sqrt expected (FDIV guard=$fd, T-Head=$th)"; return 1; }
    else
        [ "$th" = 1 ] && [ "$fd" = 0 ] || { echo "librtlsim.so lacks FPnew/T-Head (T-Head=$th, FDIV guard=$fd)"; return 1; }
    fi
    if [[ "$c" == *" -DIDIV_DISABLE "* ]]; then
        [ "$id" = 1 ] || { echo "librtlsim.so: IDIV_DISABLE requested but the IDIV guard is not compiled in"; return 1; }
    else
        [ "$id" = 0 ] || { echo "librtlsim.so has the IDIV guard but the configs keep the divider"; return 1; }
    fi
    return 0
}

# CAL energy files outside vortex/ that a row depends on (paths relative to the repository root)
# (the launcher, checker and row_accept.sh are deliberately NOT included: fixing them must not invalidate finished rows)
SIM_ENERGY_FILES="eval_perf_swemu/scripts/check_realrtl.sh eval_perf_swemu/scripts/run_single_rtlsim.sh
 eval_perf_swemu/scripts/run_parallel_rtlsim.sh eval_perf_swemu/scripts/run_single_rtlsim_memctr.sh eval_perf_swemu/scripts/run_parallel_rtlsim_memctr.sh eval_perf_swemu/scripts/workload_manifest.sh ieee_cal/analysis/workload_manifest_wave1.txt"
# (energy configs and energy_map.tsv are not hashed: a row's VX flags are checked against its own config by row_accept.sh, and the
#  launcher requires the job's configs to be committed; adding wave-2 configs or editing the layout map must not invalidate wave 1)

# sim_tree_dirty <vortex_dir> -> prints what makes the simulation build differ from the committed tree (empty = clean):
# modified tracked files in every path the rtlsim build or the workloads read, untracked sources where a build would pick
# them up, the nested Ramulator src, and the CAL energy configs and scripts. Fails CLOSED: any git error prints a line.
sim_tree_dirty() {
    local v="$1" root out rc=0
    root="$(cd "$v/.." 2>/dev/null && pwd)" || { echo "sim_tree_dirty: bad path $v"; return; }
    out=$(git -C "$v" diff --name-only HEAD -- hw/rtl hw/dpi hw/VX_config.h hw/VX_types.h sim/rtlsim sim/common sim/common.mk config.mk third_party/cvfpu \
          kernel/src kernel/include kernel/scripts kernel/softdiv/Makefile runtime/common runtime/common.mk runtime/include runtime/rtlsim runtime/stub tests/opencl/common.mk 2>&1) || rc=1
    [ -n "$out" ] && echo "$out"
    out=$(git -C "$v" diff --name-only HEAD -- tests/opencl 2>&1) || rc=1   # git errors fail closed (not filtered away)
    out=$(grep -E '\.(cc|cpp|c|h|hpp|cl|mk)$|/Makefile$' <<< "$out") ; [ -n "$out" ] && echo "$out"
    # soft-math benchmark sources (Oct 28): modified tracked sources and untracked sources (a build would compile them)
    out=$(git -C "$root" diff --name-only HEAD -- eval_perf_swemu/benchmarks_modified 2>&1) || rc=1
    out=$(grep -E '\.(cc|cpp|c|h|hpp|cl|mk)$|/Makefile$' <<< "$out") ; [ -n "$out" ] && echo "$out"
    out=$(git -C "$root" -c core.quotePath=false ls-files --others -- eval_perf_swemu/benchmarks_modified 2>&1) || rc=1   # ignore rules not applied
    out=$(grep -E '\.(cc|cpp|c|h|hpp|cl|mk)$|/(Makefile|GNUmakefile|makefile)$' <<< "$out") ; [ -n "$out" ] && echo "$out"
    # untracked sources anywhere on the builds' include paths (an untracked header earlier on -I shadows a tracked one)
    # all of hw/ (-I hw comes first in the C++ builds: any hw/<dir>/x.h shadows <dir/x.h>) except synthesis output hw/syn
    out=$(git -C "$v" -c core.quotePath=false ls-files --others -- hw ':(exclude)hw/syn' third_party/cvfpu/src third_party/cvfpu/vendor \
          sim/rtlsim sim/common runtime/include runtime/common runtime/rtlsim kernel/include kernel/src kernel/scripts 2>&1) || rc=1   # ignore rules not applied
    out=$(grep -vE '\.obj_dir/|(^|/)obj_dir/' <<< "$out" | grep -E '\.(sv|v|vh|svh|vi|inc|cpp|cc|c|h|hpp|ld|py|S|s)$|/$') ; [ -n "$out" ] && echo "$out"   # dir/ = untracked nested repo
    # tracked files hidden from git diff (assume-unchanged / skip-worktree)
    local repo lsv top
    for repo in "$v/third_party/ramulator" "$v/third_party/ramulator/ext/argparse" "$v/third_party/ramulator/ext/spdlog" "$v/third_party/ramulator/ext/yaml-cpp"; do
        top=$(git -C "$repo" rev-parse --show-toplevel 2>&1) || { rc=1; continue; }
        [ "$(cd "$repo" && pwd -P)" = "$(cd "$top" 2>/dev/null && pwd -P)" ] || echo "not its own git repository (git falls back to $top): $repo"
    done
    for repo in "$root" "$v/third_party/ramulator" "$v/third_party/ramulator/ext/argparse" "$v/third_party/ramulator/ext/spdlog" "$v/third_party/ramulator/ext/yaml-cpp"; do
        lsv=$(git -C "$repo" ls-files -v 2>&1) || { rc=1; continue; }
        out=$(grep -E '^([a-z]|S) ' <<< "$lsv") ; [ -n "$out" ] && echo "$out" | sed "s|^|hidden from git diff (${repo#$root/}): |"
    done
    # shared libraries that would shadow the pinned ones on the run's loader path (LD_LIBRARY_PATH: pocl/lib, vortex/runtime,
    # llvm-vortex/lib, and the benchmark directory via its trailing empty entry)
    out=$( { ls -d "$v/runtime"/*.so* "$root/toolchain/pocl/lib"/*.so* 2>/dev/null \
               | grep -vE '/runtime/(librtlsim\.so|libvortex-rtlsim\.so|libvortex\.so|libsimx\.so|libvortex-simx\.so|libvortex-simx\.so\.bak|librtlsim\.so\.obj_dir)$|/pocl/lib/libOpenCL\.so(\.2|\.2\.14\.0)?$';
             ls "$root/toolchain/llvm-vortex/lib"/libramulator* "$root/toolchain/llvm-vortex/lib"/librtlsim* "$root/toolchain/llvm-vortex/lib"/libvortex* \
                "$v/tests/opencl"/*/*.so* 2>/dev/null; } ) ; [ -n "$out" ] && echo "$out" | sed 's/^/loader shadow: /'
    out=$(git -C "$v/third_party/ramulator" status --porcelain --ignored -- src 2>&1) || rc=1
    [ -n "$out" ] && echo "$out" | sed 's/^/ramulator: /'
    # Ramulator's ext/ is gitignored by Ramulator; each library there is its own git repo (headers compiled into librtlsim)
    local e
    for e in argparse spdlog yaml-cpp; do
        out=$(git -C "$v/third_party/ramulator/ext/$e" status --porcelain --untracked-files=all --ignored 2>&1) || rc=1
        [ -n "$out" ] && echo "$out" | sed "s/^/ramulator ext\/$e: /"
    done
    # untracked files that can take part in a build even without a source extension (GNUmakefile/makefile win over Makefile)
    out=$(git -C "$v" -c core.quotePath=false ls-files --others -- sim/rtlsim runtime/rtlsim sim/common 2>&1) || rc=1   # ignore rules not applied
    out=$(grep -v '\.obj_dir/' <<< "$out" | grep -E '(^|/)(GNUmakefile|makefile|[^/]*\.mk)$'); [ -n "$out" ] && echo "$out"
    out=$(cd "$v/tests/opencl" && ls -d */GNUmakefile */makefile GNUmakefile makefile 2>/dev/null); [ -n "$out" ] && echo "$out" | sed 's/^/tests\/opencl\//'
    local -a ef; set -f; ef=($SIM_ENERGY_FILES); set +f   # pathspecs expanded by git, not by the shell (cwd-independent)
    out=$(git -C "$root" status --porcelain -- "${ef[@]}" 2>&1) || rc=1
    [ -n "$out" ] && echo "$out" | sed 's/^/root: /'
    [ "$rc" = 0 ] || echo "sim_tree_dirty: git error"
}

# sim_build_id <vortex_dir> -> one hash identifying everything a CAL energy row depends on: the committed trees of the build
# and workload paths (doc commits do not change it), the Ramulator commit, the installed libramulator, the energy configs and
# scripts, and the committed workload manifest (which pins the data inputs).
sim_build_id() {
    local v="$1" root
    root="$(cd "$v/.." && pwd)"
    # every tool and binary that enters the id must exist (a missing one would otherwise hash an error message)
    local need
    for need in "$v/kernel/libvortex.a" "$v/kernel/softdiv/libvortex.a" "$v/runtime/libvortex.so" "$root/toolchain/llvm-vortex/bin/clang" "$root/toolchain/pocl/lib/libOpenCL.so" \
                "$v/third_party/ramulator/libramulator.so" "$root/toolchain/libc32/lib/libc.a" "$root/toolchain/libc32/lib/libm.a" \
                "$root/toolchain/libcrt32/lib/baremetal/libclang_rt.builtins-riscv32.a" "$root/eval_perf_swemu/jobs_energy_wave1.txt" \
                "$v/third_party/softfloat/build/Linux-x86_64-GCC/softfloat.a" "$root/toolchain/pocl/lib/pocl/libpocl-devices-vortex.so" \
                "$root/toolchain/pocl/share/pocl/kernel-riscv32.bc" "$root/toolchain/pocl/share/pocl/vortex" "$root/toolchain/llvm-vortex/bin/llvm-objcopy" \
                "$root/toolchain/llvm-vortex/lib" "$root/toolchain/riscv32-gnu-toolchain/riscv32-unknown-elf/lib" \
                "$root/toolchain/pocl/share/pocl/include" "$root/toolchain/riscv32-gnu-toolchain/bin" "$v/third_party/softfloat/source/include" \
                "$root/toolchain/pocl/include"; do
        [ -e "$need" ] || { echo "BUILD_ID_ERROR_missing_$(basename "$need")"; return 1; }
    done
    command -v verilator >/dev/null || { echo "BUILD_ID_ERROR_missing_verilator"; return 1; }
    command -v g++ >/dev/null || { echo "BUILD_ID_ERROR_missing_g++"; return 1; }
    local -a ef; set -f; ef=($SIM_ENERGY_FILES); set +f   # pathspecs expanded by git, not by the shell (cwd-independent)
    {
        git -C "$v" ls-tree -r HEAD -- hw/rtl hw/dpi hw/VX_config.h hw/VX_types.h sim/rtlsim sim/common sim/common.mk config.mk \
            third_party/cvfpu kernel/src kernel/include kernel/scripts kernel/softdiv/Makefile runtime/common runtime/common.mk runtime/include runtime/rtlsim runtime/stub \
            tests/opencl/common.mk
        # benchmark trees: source files only (their tracked binaries, .depend and traces are rewritten by every build/run)
        git -C "$v" ls-tree -r HEAD -- $(git -C "$root" show HEAD:eval_perf_swemu/jobs_energy_wave1.txt | awk '{print "tests/opencl/"$3}' | sort -u) \
            | grep -E '\.(cc|cpp|c|h|hpp|cl|mk)$|/Makefile$'
        # soft-math benchmark trees (Oct 28): eval_perf_swemu/benchmarks_modified/common.mk and every job benchmark's dir, source files only
        git -C "$root" ls-tree -r HEAD -- eval_perf_swemu/benchmarks_modified/common.mk \
            $(git -C "$root" show HEAD:eval_perf_swemu/jobs_energy_wave1.txt | awk '{print "eval_perf_swemu/benchmarks_modified/"$3}' | sort -u) \
            | grep -E '\.(cc|cpp|c|h|hpp|cl|mk)$|/Makefile$'
        git -C "$v/third_party/ramulator" rev-parse HEAD
        for e in argparse spdlog yaml-cpp; do git -C "$v/third_party/ramulator/ext/$e" rev-parse HEAD; done
        md5sum < "$v/third_party/ramulator/libramulator.so"
        # prebuilt runtime pieces (built only if missing) and the toolchain that compiles and simulates
        md5sum < "$v/kernel/libvortex.a"
        md5sum < "$v/kernel/softdiv/libvortex.a"   # soft-IDIV runtime (Oct 28)
        md5sum < "$v/runtime/libvortex.so"
        verilator --version
        "$root/toolchain/llvm-vortex/bin/clang" --version | head -1
        md5sum < "$root/toolchain/pocl/lib/libOpenCL.so"
        md5sum < "$root/toolchain/libc32/lib/libc.a"; md5sum < "$root/toolchain/libc32/lib/libm.a"
        md5sum < "$root/toolchain/libcrt32/lib/baremetal/libclang_rt.builtins-riscv32.a"
        # host compiler of librtlsim, softfloat, the PoCL Vortex device and its kernel library, objcopy; the LLVM shared
        # libraries and the riscv32 sysroot by size + mtime listing (cheap: this id is computed at start and end of every run)
        g++ --version | head -1; md5sum < "$(readlink -f "$(g++ -print-file-name=libstdc++.so)")"
        md5sum < "$v/third_party/softfloat/build/Linux-x86_64-GCC/softfloat.a"
        md5sum < "$root/toolchain/pocl/lib/pocl/libpocl-devices-vortex.so"; md5sum < "$root/toolchain/pocl/share/pocl/kernel-riscv32.bc"
        cat "$root/toolchain/pocl/share/pocl/vortex"/* | md5sum; md5sum < "$root/toolchain/llvm-vortex/bin/llvm-objcopy"
        (cd "$root/toolchain" && find -L llvm-vortex/lib llvm-vortex/bin riscv32-gnu-toolchain/riscv32-unknown-elf/lib riscv32-gnu-toolchain/bin -type f -printf '%p %s %T@\n' | LC_ALL=C sort) | md5sum
        # OpenCL builtin headers of the kernel compile, softfloat headers, the python that runs vxbin.py
        (cd "$root/toolchain/pocl/share/pocl/include" && find . -type f | LC_ALL=C sort | xargs md5sum) | md5sum
        (cd "$v/third_party/softfloat/source/include" && find . -type f | LC_ALL=C sort | xargs md5sum) | md5sum
        (cd "$root/toolchain/pocl/include" && find . -type f | LC_ALL=C sort | xargs md5sum) | md5sum
        python3 --version
        # ls-tree takes literal paths: expand the glob pathspecs to the tracked files first
        mapfile -t efl < <(git -C "$root" ls-files -- $(printf ":(glob)%s " "${ef[@]}"))
        git -C "$root" ls-tree -r HEAD -- "${efl[@]}"
    } 2>&1 | sha1sum | cut -c1-16
}

# functions this file and row_accept.sh define (anything else in a real-RTL shell came from the environment)
REALRTL_OWN_FUNCS="realrtl_required|realrtl_env_dirty|realrtl_reexec_clean|sim_lib_md5s|runtime_lock_or_die|check_realrtl_configs|check_realrtl_lib|sim_tree_dirty|sim_build_id|config_fields|row_reject_reason|softmath_reason|config_override|field|realrtl_fail|fail"
