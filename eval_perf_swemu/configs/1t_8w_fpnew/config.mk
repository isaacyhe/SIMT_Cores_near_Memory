# 1t_8w_fpnew (CAL energy, Oct 25): 1t_8w + real-RTL FPU/IMUL/IDIV (-DFPU_FPNEW -DDPI_DISABLE); layout vortex_1t_8w_fpnew
# 1t_8w
# CAL extension (Oct 2026): scalar core with 8 interleaved hardware threads (UPMEM-like)

MARCH = rv32imf
MABI = ilp32f

VX_CONFIG_OVERRIDE = -DNUM_THREADS=1 -DNUM_WARPS=8 -DFPU_FPNEW -DDPI_DISABLE
