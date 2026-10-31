# dcache_512_direct_fpnew (CAL energy wave 2b, Oct 28): dcache_512_direct + real-RTL FPU/IMUL/IDIV (-DFPU_FPNEW -DDPI_DISABLE); layout vortex_dcache_512_direct_fpnew
# dcache_512_direct
# CAL extension (Oct 2026): data cache only; direct-mapped keeps 2 lines per bank

MARCH = rv32imf
MABI = ilp32f

VX_CONFIG_OVERRIDE = -DDCACHE_SIZE=512 -DDCACHE_NUM_WAYS=1 -DFPU_FPNEW -DDPI_DISABLE
