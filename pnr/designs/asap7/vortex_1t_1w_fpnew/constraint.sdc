# P&R target 1900 ps (5% over-constraint, Oct 24); timing and power are evaluated at 2000 ps (500 MHz) after routing
create_clock -name clk -period 1900 [get_ports clk]
set_input_delay 100 -clock clk [delete_from_list [all_inputs] [get_ports clk]]
set_output_delay 100 -clock clk [all_outputs]
# Top-level I/O is outside the study (core evaluated alone): exclude it from hold repair; internal hold checks stay active.
set_false_path -hold -from [delete_from_list [all_inputs] [get_ports clk]]
set_false_path -hold -to [all_outputs]
