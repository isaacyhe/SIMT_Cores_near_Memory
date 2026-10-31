# 8t_4w_fpnew (CAL energy wave 2b, Oct 28): 8t_4w + real-RTL FPU/IMUL/IDIV (-DFPU_FPNEW -DDPI_DISABLE); layout vortex_8t_4w_fpnew
# 8t_4w - Wide SIMT, default warps (8 threads x 4 warps = 32 total)
# Part of SIMT width sweep at fixed 4 warps

MARCH = rv32imf
MABI = ilp32f

# RTL overrides
VX_CONFIG_OVERRIDE = -DNUM_THREADS=8 -DNUM_WARPS=4 -DFPU_FPNEW -DDPI_DISABLE
