# one_warp - Single warp only
# Hardware FP and M extension still enabled

MARCH = rv32imf
MABI = ilp32f

# RTL overrides
VX_CONFIG_OVERRIDE = -DNUM_WARPS=1 -DNUM_BARRIERS=1
