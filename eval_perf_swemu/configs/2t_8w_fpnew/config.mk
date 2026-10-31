# 2t_8w_fpnew (CAL energy wave 2b, Oct 28): 2t_8w + real-RTL FPU/IMUL/IDIV (-DFPU_FPNEW -DDPI_DISABLE); layout vortex_2t_8w_fpnew
# 2t_8w - Narrow SIMT, many warps (2 threads x 8 warps = 16 total)
# Part of SIMT width exploration: constant 16 threads, varying width/warp ratio

MARCH = rv32imf
MABI = ilp32f

# RTL overrides
VX_CONFIG_OVERRIDE = -DNUM_THREADS=2 -DNUM_WARPS=8 -DFPU_FPNEW -DDPI_DISABLE
