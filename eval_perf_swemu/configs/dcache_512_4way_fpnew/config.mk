# dcache_512_4way_fpnew (CAL energy, Oct 25): dcache_512_4way + real-RTL FPU/IMUL/IDIV (-DFPU_FPNEW -DDPI_DISABLE); layout vortex_dcache_512_4way_fpnew
# dcache_512_4way
# CAL extension (Oct 2026): data cache 512 B at the baseline 4 ways (I-cache fixed 16 KB 4-way)

MARCH = rv32imf
MABI = ilp32f

VX_CONFIG_OVERRIDE = -DDCACHE_SIZE=512 -DFPU_FPNEW -DDPI_DISABLE
