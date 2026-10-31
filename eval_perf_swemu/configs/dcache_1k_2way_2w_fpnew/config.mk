# dcache_1k_2way_2w_fpnew (CAL energy wave 2b, Oct 28): dcache_1k_2way_2w + real-RTL FPU/IMUL/IDIV (-DFPU_FPNEW -DDPI_DISABLE); layout vortex_dcache_1k_2way_2w_fpnew
# dcache_1k_2way_2w
# CAL extension (Oct 2026): small D-cache x warp count

MARCH = rv32imf
MABI = ilp32f

VX_CONFIG_OVERRIDE = -DDCACHE_SIZE=1024 -DDCACHE_NUM_WAYS=2 -DNUM_WARPS=2 -DFPU_FPNEW -DDPI_DISABLE
