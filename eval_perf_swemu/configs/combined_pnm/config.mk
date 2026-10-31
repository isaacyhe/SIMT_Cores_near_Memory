# combined_pnm - Full PNM config
# Cache/warp: RTL changes
# FP/INT div: Software emulation via modified benchmarks

MARCH = rv32imf
MABI = ilp32f

# Use modified benchmarks with all soft math
USE_MODIFIED_BENCHMARKS = 1
CFLAGS += -DUSE_SOFT_FDIV -DUSE_SOFT_FSQRT -DUSE_SOFT_IDIV

# RTL changes for cache and warp only
VX_CONFIG_OVERRIDE = -DL1_DISABLE -DLMEM_DISABLE -DNUM_WARPS=1 -DNUM_BARRIERS=1
