# 8t_4w_no_cache_fpnew (CAL energy wave 2b, Oct 28): 8t_4w_no_cache + real-RTL FPU/IMUL/IDIV (-DFPU_FPNEW -DDPI_DISABLE); layout vortex_8t_4w_no_cache_nolmem_fpnew
# 8t_4w_no_cache - Wide SIMT + no cache, local memory retained
# 8 threads x 4 warps = 32 total, L1 cache disabled

MARCH = rv32imf
MABI = ilp32f

# RTL overrides
VX_CONFIG_OVERRIDE = -DNUM_THREADS=8 -DNUM_WARPS=4 -DL1_DISABLE -DLMEM_DISABLE -DFPU_FPNEW -DDPI_DISABLE
