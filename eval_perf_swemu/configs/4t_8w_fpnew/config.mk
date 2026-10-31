# 4t_8w_fpnew (CAL energy, Oct 25): 4t_8w + real-RTL FPU/IMUL/IDIV (-DFPU_FPNEW -DDPI_DISABLE); layout vortex_4t_8w_fpnew
# 4t_8w - Baseline width, more warps (4 threads x 8 warps = 32 total)
# Dimension 1: fix threads/warp=4, vary warp count (1, 2, 4, 8)

MARCH = rv32imf
MABI = ilp32f

# RTL overrides
VX_CONFIG_OVERRIDE = -DNUM_WARPS=8 -DFPU_FPNEW -DDPI_DISABLE
