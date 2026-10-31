# 16t_8w_fpnew (CAL energy, Oct 25): 16t_8w + real-RTL FPU/IMUL/IDIV (-DFPU_FPNEW -DDPI_DISABLE); layout vortex_16t_8w_fpnew
# 16t_8w - SIMT scaling config (16 threads x 8 warps = 128 total threads)
# For revision width-vs-depth scaling sweep (Sweep B). Hardware FP and M extension enabled.

MARCH = rv32imf
MABI = ilp32f

# RTL overrides
# Oct 27: runs at 333 1/3 MHz (3000 ps; closes neither 500 nor 400 MHz): CORE_PERIOD_PS sets the physical DRAM tick of the
# shadow refresh model (dram_sim.cpp); C++ only, no RTL effect. Job ratios are 0.067/0.667 (r x 2/3).
VX_CONFIG_OVERRIDE = -DNUM_THREADS=16 -DNUM_WARPS=8 -DFPU_FPNEW -DDPI_DISABLE -DCORE_PERIOD_PS=3000
