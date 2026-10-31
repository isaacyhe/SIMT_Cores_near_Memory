# OpenROAD Setup for ASAP7 7nm PDK
# This file configures the PDK and library paths
#
# Environment variables (optional):
#   ASAP7_DIR     - Path to ASAP7 PDK (required)
#   PVT_CORNER    - Process corner: TT, FF, SS (default: TT)
#   VT_TYPE       - Threshold voltage: RVT, LVT, SLVT (default: RVT)
#   CLK_PERIOD_NS - Clock period in ns (default: 2.0 = 500 MHz)
#   UTILIZATION   - Core utilization 0.0-1.0 (default: 0.50)

# ASAP7 PDK paths - adjust these to your installation
set ASAP7_DIR $::env(ASAP7_DIR)
if {![info exists ASAP7_DIR] || $ASAP7_DIR eq ""} {
    puts "ERROR: ASAP7_DIR environment variable not set"
    puts "Please set: export ASAP7_DIR=/path/to/asap7"
    exit 1
}

# ASAP7 subdirectory structure
set ASAP7_SC "$ASAP7_DIR/asap7sc7p5t_28"

# Process corner selection (TT=typical, FF=fast, SS=slow)
if {[info exists ::env(PVT_CORNER)]} {
    set PVT_CORNER $::env(PVT_CORNER)
} else {
    set PVT_CORNER "TT"
}

# Threshold voltage selection (RVT=regular, LVT=low, SLVT=super-low)
if {[info exists ::env(VT_TYPE)]} {
    set VT_TYPE $::env(VT_TYPE)
} else {
    set VT_TYPE "RVT"
}

# Clock period (configurable via environment)
if {[info exists ::env(CLK_PERIOD_NS)]} {
    set CLK_PERIOD $::env(CLK_PERIOD_NS)
} else {
    set CLK_PERIOD 2.0  ;# 500 MHz default
}

# Utilization (configurable via environment)
if {[info exists ::env(UTILIZATION)]} {
    set CORE_UTILIZATION $::env(UTILIZATION)
} else {
    set CORE_UTILIZATION 0.50
}

# Technology LEF
set TECH_LEF "$ASAP7_SC/techlef_misc/asap7_tech_1x_201209.lef"

# Standard cell LEFs (R=RVT, L=LVT, SL=SLVT)
set VT_SUFFIX "R"
if {$VT_TYPE eq "LVT"} { set VT_SUFFIX "L" }
if {$VT_TYPE eq "SLVT"} { set VT_SUFFIX "SL" }

set SC_LEF_LIST [list \
    "$ASAP7_SC/LEF/asap7sc7p5t_28_${VT_SUFFIX}_1x_220121a.lef" \
]

# Liberty files (based on corner and Vt selection)
# Format: asap7sc7p5t_<TYPE>_<VT>_<CORNER>_nldm_<date>.lib
# Note: Different cell types have different date stamps
set LIB_FILES [list \
    "$ASAP7_SC/LIB/NLDM/asap7sc7p5t_SEQ_${VT_TYPE}_${PVT_CORNER}_nldm_220123.lib" \
    "$ASAP7_SC/LIB/NLDM/asap7sc7p5t_OA_${VT_TYPE}_${PVT_CORNER}_nldm_211120.lib" \
    "$ASAP7_SC/LIB/NLDM/asap7sc7p5t_INVBUF_${VT_TYPE}_${PVT_CORNER}_nldm_220122.lib" \
    "$ASAP7_SC/LIB/NLDM/asap7sc7p5t_AO_${VT_TYPE}_${PVT_CORNER}_nldm_211120.lib" \
]

# Design parameters
set DESIGN_NAME "Vortex"
set CLK_PORT "clk"

# Placement parameters
set PLACE_DENSITY 0.60
set ASPECT_RATIO 1.0
set CORE_MARGIN 10

puts "============================================"
puts "ASAP7 PDK Configuration:"
puts "  PDK Path:      $ASAP7_DIR"
puts "  PVT Corner:    $PVT_CORNER (TT=typical, FF=fast, SS=slow)"
puts "  Vt Type:       $VT_TYPE (RVT=regular, LVT=low, SLVT=super-low)"
puts "  Clock Period:  ${CLK_PERIOD}ns ([expr int(1000.0/$CLK_PERIOD)] MHz)"
puts "  Utilization:   [expr int($CORE_UTILIZATION * 100)]%"
puts "============================================"
