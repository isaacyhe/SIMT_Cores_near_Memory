# 16t_16w_fpnew (CAL energy wave 2b, Oct 28): 16t_16w + real-RTL FPU/IMUL/IDIV (-DFPU_FPNEW -DDPI_DISABLE); layout vortex_16t_16w_fpnew
# 16t_16w - SIMT scaling config (16 threads x 16 warps = 256 total threads)
# For revision width-vs-depth scaling sweep (Sweep B). Hardware FP and M extension enabled.

MARCH = rv32imf
MABI = ilp32f

# RTL overrides
# Nov 1 (user): runs at 250 MHz (4000 ps; setup -707 ps at 3000, +293 ps at 4000; hold rerouted with a 150 ps margin):
# CORE_PERIOD_PS sets the physical DRAM tick of the shadow refresh model (dram_sim.cpp); C++ only, no RTL effect. Job ratios
# 0.05/0.2/0.5 (r x 1/2).
VX_CONFIG_OVERRIDE = -DNUM_THREADS=16 -DNUM_WARPS=16 -DFPU_FPNEW -DDPI_DISABLE -DCORE_PERIOD_PS=4000
