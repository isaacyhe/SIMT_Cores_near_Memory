# 32t_16w_fpnew (CAL energy wave 2b, Oct 28): 32t_16w + real-RTL FPU/IMUL/IDIV (-DFPU_FPNEW -DDPI_DISABLE); layout vortex_32t_16w_fpnew
# 32t_16w - SIMT scaling config (32 threads x 16 warps = 512 total threads)
# For revision width-vs-depth scaling sweep (Sweep B). Hardware FP and M extension enabled.

MARCH = rv32imf
MABI = ilp32f

# RTL overrides
VX_CONFIG_OVERRIDE = -DNUM_THREADS=32 -DNUM_WARPS=16 -DFPU_FPNEW -DDPI_DISABLE
