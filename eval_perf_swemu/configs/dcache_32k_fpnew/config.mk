# dcache_32k_fpnew (CAL energy, Oct 25): dcache_32k + real-RTL FPU/IMUL/IDIV (-DFPU_FPNEW -DDPI_DISABLE); layout vortex_dcache_32k_fpnew
# dcache_32k
# CAL extension (Oct 2026): data cache 32768 B, 4 ways (I-cache fixed 16 KB 4-way)

MARCH = rv32imf
MABI = ilp32f

VX_CONFIG_OVERRIDE = -DDCACHE_SIZE=32768 -DFPU_FPNEW -DDPI_DISABLE
