# half_cache_fpnew (CAL energy wave 2b, Oct 28): half_cache + real-RTL FPU/IMUL/IDIV (-DFPU_FPNEW -DDPI_DISABLE); layout vortex_half_cache_fpnew
# half_cache - 8KB 4-way I+D cache (half of default 16KB, keep associativity)
# Tests size sensitivity while holding way count constant

MARCH = rv32imf
MABI = ilp32f

# RTL overrides: halve both cache sizes, keep 4-way
VX_CONFIG_OVERRIDE = -DICACHE_SIZE=8192 -DDCACHE_SIZE=8192 -DFPU_FPNEW -DDPI_DISABLE
