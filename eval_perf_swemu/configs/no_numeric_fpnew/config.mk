# no_numeric_fpnew (CAL energy wave 2b, Oct 28): no_numeric + real-RTL FPU/IMUL/IDIV (-DFPU_FPNEW -DDPI_DISABLE); hardware the soft-math software replaces is removed as in the layout; layout vortex_no_numeric_fpnew
# no_numeric - Software emulation for FP div/sqrt and INT div
# Uses modified benchmarks with soft_math library calls
# Hardware and ISA unchanged - only div/sqrt replaced with SW routines

MARCH = rv32imf
MABI = ilp32f

# Use modified benchmarks with all soft math
USE_MODIFIED_BENCHMARKS = 1
CFLAGS += -DUSE_SOFT_FDIV -DUSE_SOFT_FSQRT -DUSE_SOFT_IDIV

# Energy config: the hardware the software replaces is removed (VX_CONFIG_OVERRIDE below), as in the layout
VX_CONFIG_OVERRIDE = -DFPU_FPNEW -DDPI_DISABLE -DFPU_DIVSQRT_DISABLE -DIDIV_DISABLE
