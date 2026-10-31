# no_intdiv - Software INT div emulation
# Uses modified benchmarks with soft_math library calls
# Hardware and ISA unchanged - only div replaced with SW routines

MARCH = rv32imf
MABI = ilp32f

# Use modified benchmarks with soft int div
USE_MODIFIED_BENCHMARKS = 1
CFLAGS += -DUSE_SOFT_IDIV

# No RTL changes - hardware intact
VX_CONFIG_OVERRIDE =
