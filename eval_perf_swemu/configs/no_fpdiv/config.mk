# no_fpdiv - Software FP div/sqrt emulation
# Uses modified benchmarks with soft_math library calls
# Hardware and ISA unchanged - only div/sqrt replaced with SW routines

MARCH = rv32imf
MABI = ilp32f

# Use modified benchmarks with soft div/sqrt
USE_MODIFIED_BENCHMARKS = 1
CFLAGS += -DUSE_SOFT_FDIV -DUSE_SOFT_FSQRT

# No RTL changes - hardware intact
VX_CONFIG_OVERRIDE =
