# 4t_2w_fpnew (CAL energy, Oct 25): 4t_2w + real-RTL FPU/IMUL/IDIV (-DFPU_FPNEW -DDPI_DISABLE); layout vortex_4t_2w_fpnew
# 4t_2w - Baseline width, reduced warps (4 threads x 2 warps = 8 total)
# Fills gap between baseline (4t_4w) and one_warp (4t_1w)

MARCH = rv32imf
MABI = ilp32f

# RTL overrides
VX_CONFIG_OVERRIDE = -DNUM_WARPS=2 -DFPU_FPNEW -DDPI_DISABLE
