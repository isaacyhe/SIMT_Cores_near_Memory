# one_warp_fpnew (CAL energy wave 2b, Oct 28): one_warp + real-RTL FPU/IMUL/IDIV (-DFPU_FPNEW -DDPI_DISABLE); layout vortex_one_warp_fpnew
# one_warp - Single warp only
# Hardware FP and M extension still enabled

MARCH = rv32imf
MABI = ilp32f

# RTL overrides
VX_CONFIG_OVERRIDE = -DNUM_WARPS=1 -DNUM_BARRIERS=1 -DFPU_FPNEW -DDPI_DISABLE
