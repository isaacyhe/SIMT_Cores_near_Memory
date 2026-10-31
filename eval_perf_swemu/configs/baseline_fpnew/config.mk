# baseline_fpnew (CAL energy, Oct 25): baseline + real-RTL FPU/IMUL/IDIV (-DFPU_FPNEW -DDPI_DISABLE); layout vortex_baseline_fpnew
# baseline - Full hardware (reference)
# Uses hardware FP and M extension

MARCH = rv32imf
MABI = ilp32f

# No RTL overrides needed
VX_CONFIG_OVERRIDE = -DFPU_FPNEW -DDPI_DISABLE
