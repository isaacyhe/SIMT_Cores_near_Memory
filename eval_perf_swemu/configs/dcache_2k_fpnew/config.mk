# dcache_2k_fpnew (CAL energy, Oct 25): dcache_2k + real-RTL FPU/IMUL/IDIV (-DFPU_FPNEW -DDPI_DISABLE); layout vortex_dcache_2k_fpnew
# dcache_2k
# CAL extension (Oct 2026): data cache only, I-cache fixed (2 lines per bank)

MARCH = rv32imf
MABI = ilp32f

VX_CONFIG_OVERRIDE = -DDCACHE_SIZE=2048 -DFPU_FPNEW -DDPI_DISABLE
