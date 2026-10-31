# icache_only_fpnew (CAL energy, Oct 25): icache_only + real-RTL FPU/IMUL/IDIV (-DFPU_FPNEW -DDPI_DISABLE); layout vortex_icache_only_fpnew
# icache_only - I-cache 16KB 4-way (default size), D-cache disabled
# Tests the effect of having only instruction cache

MARCH = rv32imf
MABI = ilp32f

# RTL overrides: disable D-cache only
VX_CONFIG_OVERRIDE = -DDCACHE_DISABLE -DFPU_FPNEW -DDPI_DISABLE
