# no_cache_lmem_fpnew (CAL energy, Oct 25): no_cache_lmem + real-RTL FPU/IMUL/IDIV (-DFPU_FPNEW -DDPI_DISABLE); layout vortex_no_cache_fpnew
# no_cache_lmem
# CAL extension (Oct 2026): 4x4 core, caches removed, scratchpad KEPT (pairs with no_cache)

MARCH = rv32imf
MABI = ilp32f

VX_CONFIG_OVERRIDE = -DL1_DISABLE -DFPU_FPNEW -DDPI_DISABLE
