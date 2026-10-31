# no_cache - L1 caches and local memory (scratchpad) disabled; matches the published runs and the P&R core
# Hardware FP and M extension still enabled

MARCH = rv32imf
MABI = ilp32f

# RTL overrides
VX_CONFIG_OVERRIDE = -DL1_DISABLE -DLMEM_DISABLE
