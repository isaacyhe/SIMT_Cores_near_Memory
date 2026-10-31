# quarter_cache_fpnew (CAL energy, Oct 25): quarter_cache + real-RTL FPU/IMUL/IDIV (-DFPU_FPNEW -DDPI_DISABLE); layout vortex_quarter_cache_fpnew
# quarter_cache - 4KB 4-way I+D cache (quarter of default 16KB, keep associativity)
# Tests size sensitivity while holding way count constant

MARCH = rv32imf
MABI = ilp32f

# RTL overrides: quarter both cache sizes, keep 4-way
VX_CONFIG_OVERRIDE = -DICACHE_SIZE=4096 -DDCACHE_SIZE=4096 -DFPU_FPNEW -DDPI_DISABLE
