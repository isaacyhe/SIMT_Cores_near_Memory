# dcache_8k_fpnew (CAL energy, Oct 25): dcache_8k + real-RTL FPU/IMUL/IDIV (-DFPU_FPNEW -DDPI_DISABLE); layout vortex_dcache_8k_fpnew
# dcache_8k
# CAL extension (Oct 2026): data cache only, I-cache fixed at 16 KB 4-way

MARCH = rv32imf
MABI = ilp32f

VX_CONFIG_OVERRIDE = -DDCACHE_SIZE=8192 -DFPU_FPNEW -DDPI_DISABLE
