# vortex_dcache_1k_2way_8w_fpnew (Oct 28, wave 2b): recipe of vortex_dcache_1k_4way_fpnew (util/density/halo/margins below); netlist spr_eval/build/dcache_1k_2way_8w_be_fpnew
export DESIGN_NAME = Vortex
export DESIGN_NICKNAME = vortex_dcache_1k_2way_8w_fpnew
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
export PLACE_DENSITY = 0.50
export MACRO_PLACE_HALO = 4 4
export NUM_CORES = 4
export SYNTH_MEMORY_MAX_BITS = 131072
