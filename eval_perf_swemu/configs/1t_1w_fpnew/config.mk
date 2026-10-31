# 1t_1w_fpnew (CAL energy, Oct 25): 1t_1w + real-RTL FPU/IMUL/IDIV (-DFPU_FPNEW -DDPI_DISABLE); layout vortex_1t_1w_fpnew
# 1t_1w
# CAL extension (Oct 2026): scalar in-order core, no multithreading (CPU end of the width axis)

MARCH = rv32imf
MABI = ilp32f

VX_CONFIG_OVERRIDE = -DNUM_THREADS=1 -DNUM_WARPS=1 -DNUM_BARRIERS=1 -DFPU_FPNEW -DDPI_DISABLE
