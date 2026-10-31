# 8t_16w_fpnew (CAL energy wave 2b, Oct 28): 8t_16w + real-RTL FPU/IMUL/IDIV (-DFPU_FPNEW -DDPI_DISABLE); layout vortex_8t_16w_fpnew
# 8t_16w - SIMT scaling config (8 threads x 16 warps = 128 total threads)
# For revision width-vs-depth scaling sweep (Sweep B). Hardware FP and M extension enabled.

MARCH = rv32imf
MABI = ilp32f

# RTL overrides
# Oct 30 (user): runs at 400 MHz (2500 ps; setup -473 ps at 2000, +27.0 ps at 2500, sta_p2500 448183): CORE_PERIOD_PS sets the
# physical DRAM tick of the shadow refresh model (dram_sim.cpp); C++ only, no RTL effect. Job ratios are 0.08/0.32/0.8 (r x 4/5).
VX_CONFIG_OVERRIDE = -DNUM_THREADS=8 -DNUM_WARPS=16 -DFPU_FPNEW -DDPI_DISABLE -DCORE_PERIOD_PS=2500
