# no_cache_fpnew (CAL energy, Oct 25): no_cache + real-RTL FPU/IMUL/IDIV (-DFPU_FPNEW -DDPI_DISABLE); layout vortex_no_cache_nolmem_fpnew
# no_cache - L1 caches and local memory (scratchpad) disabled; matches the published runs and the P&R core
# Hardware FP and M extension still enabled

MARCH = rv32imf
MABI = ilp32f

# RTL overrides
VX_CONFIG_OVERRIDE = -DL1_DISABLE -DLMEM_DISABLE -DFPU_FPNEW -DDPI_DISABLE
