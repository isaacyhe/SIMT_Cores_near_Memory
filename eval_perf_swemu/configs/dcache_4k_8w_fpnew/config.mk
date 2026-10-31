# dcache_4k_8w_fpnew (CAL energy, Oct 25): dcache_4k_8w + real-RTL FPU/IMUL/IDIV (-DFPU_FPNEW -DDPI_DISABLE); layout vortex_dcache_4k_8w_fpnew
# dcache_4k_8w
# CAL extension (Oct 2026): small D-cache x warp count

MARCH = rv32imf
MABI = ilp32f

VX_CONFIG_OVERRIDE = -DDCACHE_SIZE=4096 -DNUM_WARPS=8 -DFPU_FPNEW -DDPI_DISABLE
