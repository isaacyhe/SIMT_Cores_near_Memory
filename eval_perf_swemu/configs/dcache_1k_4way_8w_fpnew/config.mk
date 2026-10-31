# dcache_1k_4way_8w_fpnew (CAL energy, Oct 25): dcache_1k_4way_8w + real-RTL FPU/IMUL/IDIV (-DFPU_FPNEW -DDPI_DISABLE); layout vortex_dcache_1k_4way_8w_fpnew
# dcache_1k_4way_8w
# CAL extension (Oct 2026): 1 KB 4-way D-cache, 8 warps (lines-per-warp block)

MARCH = rv32imf
MABI = ilp32f

VX_CONFIG_OVERRIDE = -DDCACHE_SIZE=1024 -DNUM_WARPS=8 -DFPU_FPNEW -DDPI_DISABLE
