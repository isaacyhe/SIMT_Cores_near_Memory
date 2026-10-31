# Timing Constraints for Vortex PNM Core
# Target: ASAP7 7nm

# Clock definition
set CLK_PERIOD 2.0
set CLK_NAME clk

create_clock -name $CLK_NAME -period $CLK_PERIOD [get_ports $CLK_NAME]

# Clock uncertainty (for setup/hold)
set_clock_uncertainty 0.1 [get_clocks $CLK_NAME]

# Input/Output delays (conservative)
set_input_delay -clock $CLK_NAME [expr $CLK_PERIOD * 0.2] [all_inputs]
set_output_delay -clock $CLK_NAME [expr $CLK_PERIOD * 0.2] [all_outputs]

# Don't touch clock network

# Max fanout
set_max_fanout 20 [current_design]

# Max transition
set_max_transition 0.1 [current_design]
