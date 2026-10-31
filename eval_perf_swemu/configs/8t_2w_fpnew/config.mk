# 8t_2w_fpnew (CAL energy wave 2b, Oct 28): 8t_2w + real-RTL FPU/IMUL/IDIV (-DFPU_FPNEW -DDPI_DISABLE); layout vortex_8t_2w_fpnew
# 8t_2w - Wide SIMT, fewer warps (8 threads x 2 warps = 16 total)
# Part of SIMT width exploration: constant 16 threads, varying width/warp ratio

MARCH = rv32imf
MABI = ilp32f

# RTL overrides
VX_CONFIG_OVERRIDE = -DNUM_THREADS=8 -DNUM_WARPS=2 -DFPU_FPNEW -DDPI_DISABLE
