# vortex_32t_32w_fpnew (Oct 28, wave 2b): recipe of vortex_16t_8w_fpnew (util/density/halo/margins below); netlist spr_eval/build/32t_32w_be_fpnew
export DESIGN_NAME = Vortex
export DESIGN_NICKNAME = vortex_32t_32w_fpnew
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
export CORE_UTILIZATION = 35
export PLACE_DENSITY = 0.50
export MACRO_PLACE_HALO = 4 4
export NUM_CORES = 4
export SYNTH_MEMORY_MAX_BITS = 131072
export GPL_TIMING_DRIVEN = 0  # Oct 25: timing-driven GPL hit RSZ-1008 (FixedDelay -inf); timing is repaired at CTS/GRT
# Oct 28: flat synthesis crashed in ABC (vecPtr.h:388 assertion, 5.3 h, 53 GB); hierarchical synthesis maps module by module
export SYNTH_HIERARCHICAL = 1
# Oct 31: ABC assertion (Vec_PtrEntry) twice on the single flattened module Vortex: SYNTH_HIERARCHICAL without a threshold still flattened everything; keep modules above 50k gate equivalents so ABC maps each separately
export SYNTH_MINIMUM_KEEP_SIZE = 50000
