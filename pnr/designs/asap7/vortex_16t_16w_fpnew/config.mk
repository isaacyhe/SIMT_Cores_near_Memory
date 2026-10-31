# vortex_16t_16w_fpnew (Oct 28, wave 2b): recipe of vortex_16t_8w_fpnew (util/density/halo/margins below); netlist spr_eval/build/16t_16w_be_fpnew
export DESIGN_NAME = Vortex
export DESIGN_NICKNAME = vortex_16t_16w_fpnew
export PLATFORM = asap7
export CORNER = TC
export VERILOG_FILES = $(DESIGN_DIR)/project.v \
    $(PLATFORM_DIR)/verilog/fakeram7_2x32_be.v \
    $(PLATFORM_DIR)/verilog/fakeram7_4x32_be.v \
    $(PLATFORM_DIR)/verilog/fakeram7_8x32_be.v \
    $(PLATFORM_DIR)/verilog/fakeram7_16x32_be.v \
    $(PLATFORM_DIR)/verilog/fakeram7_32x32_be.v \
    $(PLATFORM_DIR)/verilog/fakeram7_64x32_be.v \
    $(PLATFORM_DIR)/verilog/fakeram7_128x32_be.v \
    $(PLATFORM_DIR)/verilog/fakeram7_256x32_be.v \
    $(PLATFORM_DIR)/verilog/fakeram7_512x32_be.v \
    $(PLATFORM_DIR)/verilog/fakeram7_1024x32_be.v
export SDC_FILE = $(DESIGN_DIR)/constraint.sdc
export ADDITIONAL_LEFS = \
    $(PLATFORM_DIR)/lef/fakeram7_2x32_be.lef \
    $(PLATFORM_DIR)/lef/fakeram7_4x32_be.lef \
    $(PLATFORM_DIR)/lef/fakeram7_8x32_be.lef \
    $(PLATFORM_DIR)/lef/fakeram7_16x32_be.lef \
    $(PLATFORM_DIR)/lef/fakeram7_32x32_be.lef \
    $(PLATFORM_DIR)/lef/fakeram7_64x32_be.lef \
    $(PLATFORM_DIR)/lef/fakeram7_128x32_be.lef \
    $(PLATFORM_DIR)/lef/fakeram7_256x32_be.lef \
    $(PLATFORM_DIR)/lef/fakeram7_512x32_be.lef \
    $(PLATFORM_DIR)/lef/fakeram7_1024x32_be.lef
export ADDITIONAL_LIBS = \
    $(PLATFORM_DIR)/lib/NLDM/fakeram7_2x32_be.lib \
    $(PLATFORM_DIR)/lib/NLDM/fakeram7_4x32_be.lib \
    $(PLATFORM_DIR)/lib/NLDM/fakeram7_8x32_be.lib \
    $(PLATFORM_DIR)/lib/NLDM/fakeram7_16x32_be.lib \
    $(PLATFORM_DIR)/lib/NLDM/fakeram7_32x32_be.lib \
    $(PLATFORM_DIR)/lib/NLDM/fakeram7_64x32_be.lib \
    $(PLATFORM_DIR)/lib/NLDM/fakeram7_128x32_be.lib \
    $(PLATFORM_DIR)/lib/NLDM/fakeram7_256x32_be.lib \
    $(PLATFORM_DIR)/lib/NLDM/fakeram7_512x32_be.lib \
    $(PLATFORM_DIR)/lib/NLDM/fakeram7_1024x32_be.lib
export PDN_TCL = $(DESIGN_DIR)/pdn.tcl
export CORE_UTILIZATION = 25
# Oct 28: util 35 + density 0.40 -> GPL raised the target to 0.41 (free area) and diverged again (GPL-0307); util 25 gives the placer room
export PLACE_DENSITY = 0.40
# Oct 28: first run hit GPL-0307 (RePlAce divergence) at density 0.50; 0.40 as dcache_32k and 4t_8w
export MACRO_PLACE_HALO = 4 4
export NUM_CORES = 4
export SYNTH_MEMORY_MAX_BITS = 131072
export GPL_TIMING_DRIVEN = 0  # Oct 25: timing-driven GPL hit RSZ-1008 (FixedDelay -inf); timing is repaired at CTS/GRT
# Oct 31: GPL-0307 divergence in 3_1 skip-io placement three times (util 35/0.50 and 25/0.40); the tool advises a smaller max phi coefficient (default 1.05)
export GLOBAL_PLACEMENT_ARGS = -max_phi_coef 1.03
# Nov 1 (user): first route (no hold margin, ORFS default 0) fails hold by 94.3 ps at every clock; setup closes only at 4000 ps (+293); deep 1.86 ns clock tree, 704k flops. Signs off at 250 MHz; rerun from CTS with a 150 ps hold margin (attempt in attempts/fpnew_b3_16t_16w_hold0)
export HOLD_SLACK_MARGIN = 150
