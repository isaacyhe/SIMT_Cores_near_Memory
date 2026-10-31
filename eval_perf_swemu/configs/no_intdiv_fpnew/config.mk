# no_intdiv_fpnew (CAL energy wave 2b, Oct 28): no_intdiv + real-RTL FPU/IMUL/IDIV (-DFPU_FPNEW -DDPI_DISABLE); hardware the soft-math software replaces is removed as in the layout; layout vortex_no_intdiv_fpnew
# no_intdiv - Software INT div emulation
# Uses modified benchmarks with soft_math library calls
# Hardware and ISA unchanged - only div replaced with SW routines

MARCH = rv32imf
MABI = ilp32f

# Use modified benchmarks with soft int div
USE_MODIFIED_BENCHMARKS = 1
CFLAGS += -DUSE_SOFT_IDIV

# Energy config: the hardware the software replaces is removed (VX_CONFIG_OVERRIDE below), as in the layout
VX_CONFIG_OVERRIDE = -DFPU_FPNEW -DDPI_DISABLE -DIDIV_DISABLE
