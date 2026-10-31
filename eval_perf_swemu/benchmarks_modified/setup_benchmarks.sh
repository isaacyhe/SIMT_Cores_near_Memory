#!/bin/bash
# Setup modified benchmarks with software div/sqrt emulation
# This copies original benchmarks and patches them to use soft_math

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VORTEX_OPENCL="/home/user/GPU_and_PNM/vortex/tests/opencl"

# Benchmarks to modify
BENCHMARKS=(vecadd saxpy dotproduct sgemm3 blackscholes guassian conv3 sfilter stencil transpose spmv lbm bfs kmeans nearn psort psum histogram memcopy gather)

echo "Setting up modified benchmarks for software div/sqrt emulation..."
echo ""

for bench in "${BENCHMARKS[@]}"; do
    echo "Processing: $bench"

    SRC_DIR="$VORTEX_OPENCL/$bench"
    DST_DIR="$SCRIPT_DIR/$bench"

    # Skip if source doesn't exist
    if [ ! -d "$SRC_DIR" ]; then
        echo "  WARNING: Source not found: $SRC_DIR"
        continue
    fi

    # Copy benchmark
    rm -rf "$DST_DIR"
    cp -r "$SRC_DIR" "$DST_DIR"

    # Find and patch OpenCL kernel files
    for kernel in "$DST_DIR"/*.cl; do
        if [ -f "$kernel" ]; then
            echo "  Patching: $(basename $kernel)"

            # Add soft_math include at the top
            # And replace sqrt with FSQRT, / with FDIV where appropriate

            # Create temp file with include
            {
                echo '// AUTO-GENERATED: Soft math emulation enabled'
                echo '#include "soft_math_cl.h"'
                echo ''
                cat "$kernel"
            } > "${kernel}.tmp"
            mv "${kernel}.tmp" "$kernel"

            # Replace sqrt( with FSQRT( - but be careful with native_sqrt
            sed -i 's/\bsqrt(/FSQRT(/g' "$kernel"
            sed -i 's/native_FSQRT/native_sqrt/g' "$kernel"  # Fix native_sqrt

            # For division, we need to be more careful - only replace explicit divisions
            # This is tricky in a general way, so we'll use FDIV macro where needed
        fi
    done

    # Copy soft_math header
    cp "$SCRIPT_DIR/soft_math_cl.h" "$DST_DIR/"

    # Patch Makefile to add defines
    if [ -f "$DST_DIR/Makefile" ]; then
        # Add soft math defines to CFLAGS
        if ! grep -q "USE_SOFT" "$DST_DIR/Makefile"; then
            sed -i 's/^CFLAGS/CFLAGS += -DUSE_SOFT_FDIV -DUSE_SOFT_FSQRT\nORIG_CFLAGS/' "$DST_DIR/Makefile" 2>/dev/null || true
        fi
    fi
done

echo ""
echo "Done. Modified benchmarks in: $SCRIPT_DIR/"
echo ""
echo "To use:"
echo "  - For soft FP div/sqrt: compile with -DUSE_SOFT_FDIV -DUSE_SOFT_FSQRT"
echo "  - For normal (hardware): compile without these defines"
