# 8t_1w_no_cache_fpnew (CAL energy wave 2b, Oct 28): 8t_1w_no_cache + real-RTL FPU/IMUL/IDIV (-DFPU_FPNEW -DDPI_DISABLE); layout vortex_8t_1w_no_cache_nolmem_fpnew
# 8t_1w_no_cache - Wide SIMT, single warp, no cache, local memory retained
# 8 threads x 1 warp = 8 total, L1 cache disabled

MARCH = rv32imf
MABI = ilp32f

# RTL overrides
VX_CONFIG_OVERRIDE = -DNUM_THREADS=8 -DNUM_WARPS=1 -DL1_DISABLE -DLMEM_DISABLE -DFPU_FPNEW -DDPI_DISABLE
