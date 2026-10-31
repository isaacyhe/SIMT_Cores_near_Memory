# dcache_1k_2way_fpnew (CAL energy wave 2b, Oct 28): dcache_1k_2way + real-RTL FPU/IMUL/IDIV (-DFPU_FPNEW -DDPI_DISABLE); layout vortex_dcache_1k_2way_fpnew
# dcache_1k_2way
# CAL extension (Oct 2026): data cache only; 2-way keeps 2 lines per bank

MARCH = rv32imf
MABI = ilp32f

VX_CONFIG_OVERRIDE = -DDCACHE_SIZE=1024 -DDCACHE_NUM_WAYS=2 -DFPU_FPNEW -DDPI_DISABLE
