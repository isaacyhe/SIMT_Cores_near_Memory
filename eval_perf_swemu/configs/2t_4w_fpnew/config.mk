# 2t_4w_fpnew (CAL energy wave 2b, Oct 28): 2t_4w + real-RTL FPU/IMUL/IDIV (-DFPU_FPNEW -DDPI_DISABLE); layout vortex_2t_4w_fpnew
# 2t_4w - Narrow SIMT, default warps (2 threads x 4 warps = 8 total)
# Part of SIMT width sweep at fixed 4 warps

MARCH = rv32imf
MABI = ilp32f

# RTL overrides
VX_CONFIG_OVERRIDE = -DNUM_THREADS=2 -DNUM_WARPS=4 -DFPU_FPNEW -DDPI_DISABLE
