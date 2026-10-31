# vortex_32t_8w_fpnew (Oct 28, wave 2b): recipe of vortex_16t_8w_fpnew (util/density/halo/margins below); netlist spr_eval/build/32t_8w_be_fpnew
export DESIGN_NAME = Vortex
export DESIGN_NICKNAME = vortex_32t_8w_fpnew
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
export PLACE_DENSITY = 0.40
export MACRO_PLACE_HALO = 4 4
export NUM_CORES = 4
export SYNTH_MEMORY_MAX_BITS = 131072
export GPL_TIMING_DRIVEN = 0  # Oct 25: timing-driven GPL hit RSZ-1008 (FixedDelay -inf); timing is repaired at CTS/GRT
# Oct 31: 24 h limit hit inside global routing (30 + 30 extra congestion iterations, single-threaded); finish GRT with residual overflow and let detailed routing clear it (DRC checked at 6_report)
export GLOBAL_ROUTE_ARGS = -congestion_iterations 15 -congestion_report_iter_step 5 -verbose -allow_congestion
# Oct 31: at util 35 / density 0.50 global routing ended with congestion (GRT-0116; 32t_8w: 342k overflow at 40% average usage, local hot spots), attempt in attempts/fpnew_b3_32t_8w_util35; util 25 / density 0.40 as 8t_32w and 16t_16w (all wide designs alike), with their placement fix
export GLOBAL_PLACEMENT_ARGS = -max_phi_coef 1.03
