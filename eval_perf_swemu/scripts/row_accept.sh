#!/bin/bash
# CAL energy row acceptance (sourced by run_energy_wave.sh and check_energy_wave.sh; NOT part of the build id, so fixing the
# checker never invalidates finished rows). Requires check_realrtl.sh to be sourced first (check_realrtl_configs).
#
# directory of this file, resolved when it is sourced (the identity checker lives next to it)
RA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# config_fields <eval_dir> <config> -> "march mabi extra_cflags use_modified" parsed exactly as run_single does (with its defaults)
config_fields() {
    local march="rv32imf" mabi="ilp32f" cflags="" usemod="0" line
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*MARCH[[:space:]]*=[[:space:]]*(.+)$ ]] && march="${BASH_REMATCH[1]}"
        [[ "$line" =~ ^[[:space:]]*MABI[[:space:]]*=[[:space:]]*(.+)$ ]] && mabi="${BASH_REMATCH[1]}"
        [[ "$line" =~ ^[[:space:]]*CFLAGS[[:space:]]*\+=[[:space:]]*(.+)$ ]] && cflags="$cflags ${BASH_REMATCH[1]}"
        [[ "$line" =~ ^[[:space:]]*USE_MODIFIED_BENCHMARKS[[:space:]]*=[[:space:]]*(.+)$ ]] && usemod="${BASH_REMATCH[1]}"
    done < "$1/configs/$2/config.mk"
    printf '%s\t%s\t%s\t%s\n' "$march" "$mabi" "$cflags" "$usemod"
}

# row_reject_reason <result_file> <build_id> <libramulator_md5_12> <config> <ratio> <bench> <args> <size> <vx_config_override>
# prints every reason the row is NOT acceptable (empty = accepted).
row_reject_reason() {
    local f="$1" bid="$2" lib="$3" cfg="$4" r="$5" bench="$6" args="$7" size="$8" ov="$9"
    local v n
    [ -f "$f" ] || { echo "missing"; return; }
    field() { grep -m1 -oP "^$1=\K.*" "$f"; }
    for v in status ctr_status ctr_error ctr_file dram_file realrtl_verified build_id config mem_ratio benchmark input_size opts \
             rtlsim_configs cycles instructions provenance dram_sum_drained dram_sum_shadow_mode lib_md5_stamp lib_md5_start \
             lib_md5_end run_end_check runner bench_md5 bench_md5_end run_rc self_check; do
        n=$(grep -c "^$v=" "$f"); [ "$n" = "1" ] || echo "$v appears $n times"
    done
    local dup; dup=$(awk -F= '/=/{c[$1]++} END{for(k in c) if(c[k]>1) printf "%s ", k}' "$f")
    [ -z "$dup" ] || echo "duplicate keys: $dup"
    # expected verdict: these benchmarks have no self-check and end COMPLETED; every other one must PASS
    case "$bench" in
        bfs|nearn) [[ "$(field status)" =~ ^(PASSED|COMPLETED)$ ]] || echo "status=$(field status)" ;;
        guassian|kmeans) [[ "$(field status)" =~ ^(PASSED|COMPLETED)$ ]] || echo "status=$(field status)" ;;
        *) [ "$(field status)" = "PASSED" ] || echo "status=$(field status) (benchmark $bench must PASS)" ;;
    esac
    # every benchmark with a self-check (all but guassian, kmeans) printed its own pass line and no failure line
    case "$bench" in guassian|kmeans) ;; *)
        [[ "$(field self_check)" =~ ^passed:[1-9][0-9]*\ failed:0$ ]] || echo "$bench self_check=[$(field self_check)] (needs its own pass line and no failure line)" ;;
    esac
    [ "$(field ctr_status)" = "OK" ] || echo "ctr_status=$(field ctr_status)"
    [ -z "$(field ctr_error)" ] || echo "ctr_error=$(field ctr_error)"
    [ "$(field realrtl_verified)" = "1" ] || echo "realrtl_verified=$(field realrtl_verified)"
    [ "$(field build_id)" = "$bid" ] || echo "build_id=$(field build_id) (current $bid)"
    # the row belongs to this job
    [ "$(field config)" = "$cfg" ] || echo "config=$(field config) (job $cfg)"
    [ "$(field mem_ratio)" = "$r" ] || echo "mem_ratio=$(field mem_ratio) (job $r)"
    [ "$(field benchmark)" = "$bench" ] || echo "benchmark=$(field benchmark) (job $bench)"
    [ "$(field input_size)" = "$size" ] || echo "input_size=$(field input_size) (job $size)"
    local jargs="$args"; [ "$jargs" = "_" ] && jargs=""          # "_" in a job line = default arguments (recorded as empty)
    [ "$(field opts)" = "$jargs" ] || echo "opts=$(field opts) (job $args)"
    # toolchain fields from the job's config (march, mabi, extra CFLAGS, modified benchmarks)
    local cfgf rowf ed="${EVAL_DIR:-$(dirname "$RA_DIR")}"
    if [ ! -f "$ed/configs/$cfg/config.mk" ]; then echo "config file not found: $ed/configs/$cfg/config.mk"; fi
    cfgf=$(config_fields "$ed" "$cfg" 2>/dev/null)
    rowf=$(printf '%s\t%s\t%s\t%s\n' "$(field march)" "$(field mabi)" "$(field extra_cflags)" "$(field use_modified)")
    [ "$rowf" = "$cfgf" ] || echo "march/mabi/extra_cflags/use_modified [$(tr '\t' '|' <<< "$rowf")] != config [$(tr '\t' '|' <<< "$cfgf")]"
    # stock benchmarks, or the soft-math benchmarks with the replaced hardware removed (softmath_reason, Oct 28)
    softmath_reason "$(field use_modified)" "$(field extra_cflags)" "$ov"
    # kernel runtime library: kernel/softdiv/libvortex.a exactly for soft-IDIV rows, kernel/libvortex.a otherwise; md5 = the installed file
    local klib="kernel/libvortex.a"
    [ "$(field use_modified)" = "1" ] && [[ " $(field extra_cflags) " == *" -DUSE_SOFT_IDIV "* ]] && klib="kernel/softdiv/libvortex.a"
    # rows made before Oct 28 have no kernel_lib field: they are stock rows (the soft-IDIV runtime did not exist; the build id differs too)
    if [ "$klib" != "kernel/libvortex.a" ] || grep -q '^kernel_lib=' "$f"; then
        [ "$(field kernel_lib)" = "$klib" ] || echo "kernel_lib=[$(field kernel_lib)] (expected $klib)"
        local kmd5; kmd5=$( { md5sum < "$(dirname "$ed")/vortex/$klib"; } 2>/dev/null | cut -c1-12)
        [[ "$(field kernel_lib_md5)" =~ ^[0-9a-f]{12}$ ]] && [ "$(field kernel_lib_md5)" = "$kmd5" ] || echo "kernel_lib_md5=[$(field kernel_lib_md5)] != installed $klib [$kmd5]"
    fi
    [ "$(field runner)" = "run_single_rtlsim.sh" ] || echo "runner=$(field runner) (energy rows come from run_single_rtlsim.sh)"
    # the benchmark binary that ran: hashed before the run and again at the end (a concurrent rebuild would differ)
    [[ "$(field bench_md5)" =~ ^[0-9a-f]{12}$ ]] && [ "$(field bench_md5_end)" = "$(field bench_md5)" ] || echo "bench_md5=[$(field bench_md5)] bench_md5_end=[$(field bench_md5_end)]"
    # the build: expected flags from the job's config, real-RTL flags, stamped build flags equal
    local rc exp prov bc
    rc=$(echo $(field rtlsim_configs)); exp=$(echo "-DMEM_CLOCK_RATIO=$r $ov -DVERILATOR_RESET_VALUE=0")   # energy rows: zero-init build (Oct 26)
    [ "$rc" = "$exp" ] || echo "rtlsim_configs=[$rc] (expected [$exp])"
    check_realrtl_configs "$rc" >/dev/null || echo "rtlsim_configs fail the real-RTL check: $(check_realrtl_configs "$rc")"
    prov=$(field provenance); bc=$(sed -n 's/.*build_configs=\([^ ]*\).*/\1/p' <<< "$prov")
    [ "$(echo $rc | tr ' ' ',')" = "$bc" ] || echo "build_configs=$bc != rtlsim_configs"
    [[ "$prov" == *"libramulator=$lib"* ]] || echo "libramulator not $lib"
    [[ "$prov" != *"+dirty"* ]] || echo "dirty build"
    # the run loaded the library its group built: stamp = start = end, and the provenance md5 is that library
    local ls lmd5=""; ls=$(field lib_md5_stamp)
    if [[ "$ls" =~ ^librtlsim=([0-9a-f]{12})\ libvortex=[0-9a-f]{12}$ ]]; then lmd5="${BASH_REMATCH[1]}"; else echo "lib_md5_stamp=$ls"; fi
    [ "$(field lib_md5_start)" = "$ls" ] && [ "$(field lib_md5_end)" = "$ls" ] || echo "libraries at start/end [$(field lib_md5_start)] [$(field lib_md5_end)] != stamp [$ls]"
    [[ -n "$lmd5" && "$prov" == "librtlsim=$lmd5 "* ]] || echo "provenance librtlsim is not the stamped library"
    [ "$(field run_end_check)" = "OK" ] || echo "run_end_check=$(field run_end_check)"
    # the results exist and are complete
    [[ "$(field cycles)" =~ ^[1-9][0-9]*$ ]] || echo "cycles=$(field cycles)"
    [[ "$(field instructions)" =~ ^[1-9][0-9]*$ ]] || echo "instructions=$(field instructions)"
    # the counter and DRAM files are the row's own siblings (portable if results are copied between machines)
    local cf="${f%.txt}.ctr.gz" df="${f%.txt}.dram.tgz"
    [ "$(basename "$(field ctr_file)")" = "$(basename "$cf")" ] || echo "ctr_file=$(field ctr_file) is not this row's ($cf)"
    [ "$(basename "$(field dram_file)")" = "$(basename "$df")" ] || echo "dram_file=$(field dram_file) is not this row's ($df)"
    if gzip -t "$cf" 2>/dev/null && tar -tzf "$df" >/dev/null 2>&1; then
        # content: complete files and every counter / DRAM identity. Fails closed: the checker must exit 0 AND print the sentinel.
        local idout idrc
        idout=$(python3 -I "$RA_DIR/row_identities.py" "$f" "$cf" "$df" 2>&1); idrc=$?
        if [ "$idrc" != "0" ] || [ "$(tail -n 1 <<< "$idout")" != "IDENTITIES_OK" ]; then
            echo "identities (rc=$idrc): $(tr '\n' ' ' <<< "$idout")"
        fi
    else
        echo "ctr/dram files missing or corrupt ($cf, $df)"
    fi
    [ "$(field dram_sum_drained)" = "1" ] || echo "dram_sum_drained=$(field dram_sum_drained)"
    [ "$(field dram_sum_shadow_mode)" = "physical" ] || echo "dram_sum_shadow_mode=$(field dram_sum_shadow_mode)"
}

# config_override <eval_dir> <config> -> the VX_CONFIG_OVERRIDE of a config, parsed line by line exactly as run_single does
# softmath_reason <use_modified> <extra_cflags> <vx_config_override> -> prints why the combination is not allowed (empty = ok).
# Energy configs use the stock benchmarks (use_modified 0, no CFLAGS) or the soft-math benchmarks (eval_perf_swemu/benchmarks_modified,
# hashed into the build id since Oct 28) whose software replacement matches the removed hardware: -DUSE_SOFT_FDIV and -DUSE_SOFT_FSQRT
# together <=> -DFPU_DIVSQRT_DISABLE (FPnew has one div/sqrt unit), -DUSE_SOFT_IDIV <=> -DIDIV_DISABLE.
softmath_reason() {
    local um="$1" cf=" $2 " ov=" $(echo $3) " t sf=0 sq=0 si=0
    # whitespace normalised (tabs); only the bare -D forms count, so refuse -U or -D...=value of these macros
    for t in $3; do
        case "$t" in -UFPU_DIVSQRT_DISABLE*|-UIDIV_DISABLE*|-DFPU_DIVSQRT_DISABLE=*|-DIDIV_DISABLE=*) echo "VX_CONFIG_OVERRIDE token '$t' not allowed (use the bare -D form)" ;; esac
    done
    for t in $2; do
        case "$t" in -DUSE_SOFT_FDIV) sf=1 ;; -DUSE_SOFT_FSQRT) sq=1 ;; -DUSE_SOFT_IDIV) si=1 ;; *) echo "extra CFLAGS token '$t' not allowed (only -DUSE_SOFT_FDIV/FSQRT/IDIV)" ;; esac
    done
    case "$um" in 0) [ -z "${2// /}" ] || echo "CFLAGS [$2] without USE_MODIFIED_BENCHMARKS=1" ;;
                  1) [ $((sf + sq + si)) -gt 0 ] || echo "USE_MODIFIED_BENCHMARKS=1 without a soft-math CFLAG" ;;
                  *) echo "USE_MODIFIED_BENCHMARKS=[$um] (expected 0 or 1)" ;; esac
    [ "$sf" = "$sq" ] || echo "USE_SOFT_FDIV=$sf but USE_SOFT_FSQRT=$sq (one FPnew div/sqrt unit: both or neither)"
    local hd=0 hi=0
    [[ "$ov" == *" -DFPU_DIVSQRT_DISABLE "* ]] && hd=1
    [[ "$ov" == *" -DIDIV_DISABLE "* ]] && hi=1
    [ "$sf" = "$hd" ] || echo "soft FDIV/FSQRT=$sf but -DFPU_DIVSQRT_DISABLE=$hd in VX_CONFIG_OVERRIDE"
    [ "$si" = "$hi" ] || echo "soft IDIV=$si but -DIDIV_DISABLE=$hi in VX_CONFIG_OVERRIDE"
}

config_override() {
    local ov="" line
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*VX_CONFIG_OVERRIDE[[:space:]]*=[[:space:]]*(.+)$ ]] && ov="${BASH_REMATCH[1]}"
    done < "$1/configs/$2/config.mk"
    echo $ov
}
