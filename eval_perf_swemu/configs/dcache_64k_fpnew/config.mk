# dcache_64k_fpnew (CAL energy, Oct 25): dcache_64k + real-RTL FPU/IMUL/IDIV (-DFPU_FPNEW -DDPI_DISABLE); layout vortex_dcache_64k_fpnew
# dcache_64k
# CAL extension (Oct 2026): data cache 65536 B, 4 ways (I-cache fixed 16 KB 4-way)

MARCH = rv32imf
MABI = ilp32f

VX_CONFIG_OVERRIDE = -DDCACHE_SIZE=65536 -DFPU_FPNEW -DDPI_DISABLE
