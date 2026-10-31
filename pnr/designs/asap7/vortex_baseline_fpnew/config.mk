export DESIGN_NAME = Vortex
export DESIGN_NICKNAME = vortex_baseline_fpnew
export PLATFORM = asap7
# TT libraries (ORFS asap7 typical corner name is TC, 0.70 V)
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
export CORE_UTILIZATION = 30
export PLACE_DENSITY = 0.50
export MACRO_PLACE_HALO = 4 4
export NUM_CORES = 4
export SYNTH_MEMORY_MAX_BITS = 131072
# Oct 25: first T-Head route missed 500 MHz by 2.4 ps (setup) and -84 ps hold at icache SRAM inputs after detailed route; rerun with repair margins (hold margin 100 hit RSZ-0060 max buffer count: 113k hold buffers; now 30)
export HOLD_SLACK_MARGIN = 30
# SETUP_SLACK_MARGIN removed (Oct 26)
# Oct 25: halo 4 routed the 132-macro clock tree with slow wires (macro clk 1370 ps vs regs ~650 after route; the post-CTS estimate was balanced: macros 802-943 vs regs 874-968). Back to halo 2 (first T-Head route: macro clk 899 ps, -2.4 ps setup / -84 ps hold) with the repair margins above. macro_clustering_size 1 is broken in this OpenROAD (0 clusters / segfault).
# Oct 26: every util-40 attempt missed 500 MHz (halo 2: -2.4/-84 ps; halo 4: macro clock 1370 ps; halo 2 + margins: -176 ps after GRT, then a
# GRT hang). util 30 / density 0.50 / halo 4 / HOLD_SLACK_MARGIN 30 (variant u30, = dcache_4k recipe) passes: 2000 ps setup +127.3, hold +35.5,
# DRC 0. util 25 (u25) also passes (+174.4 / +25.3), kept as variant u25.
