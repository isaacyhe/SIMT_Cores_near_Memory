# 1t_8w_icache_only_fpnew (CAL energy wave 2b, Oct 28): 1t_8w_icache_only + real-RTL FPU/IMUL/IDIV (-DFPU_FPNEW -DDPI_DISABLE); layout vortex_1t_8w_icache_only_fpnew
# 1t_8w_icache_only
# CAL extension (Oct 2026): scalar 8-warp core, instruction cache only

MARCH = rv32imf
MABI = ilp32f

VX_CONFIG_OVERRIDE = -DNUM_THREADS=1 -DNUM_WARPS=8 -DDCACHE_DISABLE -DFPU_FPNEW -DDPI_DISABLE
