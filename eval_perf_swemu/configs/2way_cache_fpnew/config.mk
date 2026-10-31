# 2way_cache_fpnew (CAL energy wave 2b, Oct 28): 2way_cache + real-RTL FPU/IMUL/IDIV (-DFPU_FPNEW -DDPI_DISABLE); layout vortex_2way_cache_fpnew
# 2way_cache - 16KB 2-way I+D cache (keep size, reduce associativity)
# Tests associativity sensitivity while holding size constant

MARCH = rv32imf
MABI = ilp32f

# RTL overrides
VX_CONFIG_OVERRIDE = -DICACHE_NUM_WAYS=2 -DDCACHE_NUM_WAYS=2 -DFPU_FPNEW -DDPI_DISABLE
