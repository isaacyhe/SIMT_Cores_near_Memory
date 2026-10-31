# direct_cache_fpnew (CAL energy, Oct 25): direct_cache + real-RTL FPU/IMUL/IDIV (-DFPU_FPNEW -DDPI_DISABLE); layout vortex_direct_cache_fpnew
# direct_cache - 16KB direct-mapped (1-way) I+D cache (keep size, minimum associativity)
# Tests associativity sensitivity while holding size constant

MARCH = rv32imf
MABI = ilp32f

# RTL overrides: direct-mapped, keep 16KB size
VX_CONFIG_OVERRIDE = -DICACHE_NUM_WAYS=1 -DDCACHE_NUM_WAYS=1 -DFPU_FPNEW -DDPI_DISABLE
