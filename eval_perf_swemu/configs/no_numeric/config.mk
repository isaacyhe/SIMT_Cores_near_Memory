# no_numeric - Software emulation for FP div/sqrt and INT div
# Uses modified benchmarks with soft_math library calls
# Hardware and ISA unchanged - only div/sqrt replaced with SW routines

MARCH = rv32imf
MABI = ilp32f

# Use modified benchmarks with all soft math
USE_MODIFIED_BENCHMARKS = 1
CFLAGS += -DUSE_SOFT_FDIV -DUSE_SOFT_FSQRT -DUSE_SOFT_IDIV

# No RTL changes - hardware intact
VX_CONFIG_OVERRIDE =
