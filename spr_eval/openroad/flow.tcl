# OpenROAD Flow Script for Vortex PNM Evaluation
# Usage: openroad -exit flow.tcl

# Get environment variables
set CONFIG_NAME $::env(CONFIG_NAME)
set BUILD_DIR $::env(BUILD_DIR)
set RESULTS_DIR $::env(RESULTS_DIR)
set OPENROAD_DIR $::env(OPENROAD_DIR)

puts "=========================================="
puts "OpenROAD Flow for: $CONFIG_NAME"
puts "=========================================="

# Source setup
source "$OPENROAD_DIR/setup.tcl"

#----------------------------------------------------------
# Step 1: Read Design
#----------------------------------------------------------
puts "\n>>> Step 1: Reading Design"

# Read liberty
foreach lib $LIB_FILES {
    if {[file exists $lib]} {
        read_liberty $lib
        puts "  Read: $lib"
    } else {
        puts "  WARNING: Library not found: $lib"
    }
}

# Read LEF
read_lef $TECH_LEF
foreach lef $SC_LEF_LIST {
    if {[file exists $lef]} {
        read_lef $lef
        puts "  Read: $lef"
    }
}

# Read synthesized Verilog
set SYNTH_VERILOG "$BUILD_DIR/synth.v"
if {[file exists $SYNTH_VERILOG]} {
    read_verilog $SYNTH_VERILOG
    puts "  Read: $SYNTH_VERILOG"
} else {
    puts "ERROR: Synthesized netlist not found: $SYNTH_VERILOG"
    exit 1
}

link_design $DESIGN_NAME

# Read constraints
read_sdc "$OPENROAD_DIR/constraints.sdc"

#----------------------------------------------------------
# Step 2: Floorplan
#----------------------------------------------------------
puts "\n>>> Step 2: Floorplanning"

initialize_floorplan \
    -utilization $CORE_UTILIZATION \
    -aspect_ratio $ASPECT_RATIO \
    -core_space $CORE_MARGIN \
    -site asap7sc7p5t

# Create power grid
source "$OPENROAD_DIR/pdn.tcl"

#----------------------------------------------------------
# Step 3: Placement
#----------------------------------------------------------
puts "\n>>> Step 3: Global Placement"

global_placement -density $PLACE_DENSITY

puts "\n>>> Step 4: Detailed Placement"
detailed_placement
check_placement

#----------------------------------------------------------
# Step 5: Clock Tree Synthesis
#----------------------------------------------------------
puts "\n>>> Step 5: Clock Tree Synthesis"

# Configure CTS
set_wire_rc -clock -layer M5
clock_tree_synthesis -root_buf CLKBUF_X2 -buf_list {CLKBUF_X2 CLKBUF_X4}

# Repair clock nets
repair_clock_nets

#----------------------------------------------------------
# Step 6: Routing
#----------------------------------------------------------
puts "\n>>> Step 6: Global Routing"

set_global_routing_layer_adjustment M2-M7 0.3
global_route -guide_file "$RESULTS_DIR/route.guide"

puts "\n>>> Step 7: Detailed Routing"
detailed_route

#----------------------------------------------------------
# Step 8: Reports
#----------------------------------------------------------
puts "\n>>> Step 8: Generating Reports"

# Area report
report_design_area > "$RESULTS_DIR/area_report.txt"

# Timing report
report_worst_slack -max > "$RESULTS_DIR/timing_setup.txt"
report_worst_slack -min > "$RESULTS_DIR/timing_hold.txt"
report_tns > "$RESULTS_DIR/timing_tns.txt"

# Power report
report_power > "$RESULTS_DIR/power_report.txt"

# DRC report
report_drc > "$RESULTS_DIR/drc_report.txt"

#----------------------------------------------------------
# Step 9: Write Outputs
#----------------------------------------------------------
puts "\n>>> Step 9: Writing Outputs"

write_def "$RESULTS_DIR/final.def"
write_verilog "$RESULTS_DIR/final.v"

#----------------------------------------------------------
# Summary
#----------------------------------------------------------
puts "\n=========================================="
puts "OpenROAD Flow Completed: $CONFIG_NAME"
puts "=========================================="

# Print key metrics
puts "Design Area:"
report_design_area

puts "\nWorst Setup Slack:"
report_worst_slack -max

puts "\nTotal Power:"
report_power

puts "\nResults saved to: $RESULTS_DIR/"
