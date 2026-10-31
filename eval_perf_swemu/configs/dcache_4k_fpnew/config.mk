# dcache_4k_fpnew (CAL energy, Oct 25): dcache_4k + real-RTL FPU/IMUL/IDIV (-DFPU_FPNEW -DDPI_DISABLE); layout vortex_dcache_4k_fpnew
# dcache_4k
# CAL extension (Oct 2026): data cache only, I-cache fixed

MARCH = rv32imf
MABI = ilp32f

VX_CONFIG_OVERRIDE = -DDCACHE_SIZE=4096 -DFPU_FPNEW -DDPI_DISABLE
