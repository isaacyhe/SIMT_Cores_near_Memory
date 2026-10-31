#!/bin/bash
# CAL energy: workload manifest. Usage: workload_manifest.sh <jobs_file>
# Prints "md5  path" (sorted) for everything the listed runs read from the workloads: the source files of each benchmark
# directory (code, kernels, Makefiles; tracked or not), every input file named in the job arguments (__ = space, comma-
# separated lists allowed), and every file listed inside a *filelist*.txt input (nearn). Data files are not in git; this
# manifest is what pins them.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
JOBS="${1:?usage: workload_manifest.sh <jobs_file>}"
OCL="$ROOT/vortex/tests/opencl"
{
    for b in $(awk '{print $3}' "$JOBS" | sort -u); do
        find "$OCL/$b" -maxdepth 1 -type f \( -name '*.cc' -o -name '*.cpp' -o -name '*.c' -o -name '*.h' -o -name '*.hpp' \
            -o -name '*.cl' -o -name 'Makefile' -o -name '*.mk' -o -name '*.gold' \) -print
    done
    echo "$OCL/common.mk"
    awk '{print $4}' "$JOBS" | sort -u | sed 's/__/ /g' | tr ' ,' '\n\n' | grep '^/' | sort -u | while read -r f; do
        echo "$f"
        case "$f" in *filelist*.txt) grep '^/' "$f" ;; esac
    done
} | sort -u | while read -r f; do
    if [ -f "$f" ]; then echo "$(md5sum < "$f" | cut -c1-32)  ${f#$ROOT/}"; else echo "MISSING  ${f#$ROOT/}"; fi
done
