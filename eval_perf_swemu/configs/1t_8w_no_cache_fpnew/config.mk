# 1t_8w_no_cache_fpnew (CAL energy, Oct 25): 1t_8w_no_cache + real-RTL FPU/IMUL/IDIV (-DFPU_FPNEW -DDPI_DISABLE); layout vortex_1t_8w_no_cache_fpnew
# 1t_8w_no_cache
# CAL extension (Oct 2026): scalar 8-warp core, cacheless (caches and scratchpad removed, as in no_cache and 8t_*_no_cache)

MARCH = rv32imf
MABI = ilp32f

VX_CONFIG_OVERRIDE = -DNUM_THREADS=1 -DNUM_WARPS=8 -DL1_DISABLE -DLMEM_DISABLE -DFPU_FPNEW -DDPI_DISABLE
