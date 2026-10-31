# Power Distribution Network for ASAP7

# Define power/ground nets
add_global_connection -net VDD -pin_pattern {^VDD$} -power
add_global_connection -net VSS -pin_pattern {^VSS$} -ground

# Set voltage domains
set_voltage_domain -name CORE -power VDD -ground VSS

# Define PDN stripes
define_pdn_grid -name main_grid -voltage_domains CORE

# Add stripes on metal layers
add_pdn_stripe -grid main_grid -layer M1 -width 0.1 -pitch 2.0 -offset 0
add_pdn_stripe -grid main_grid -layer M4 -width 0.5 -pitch 20.0 -offset 2
add_pdn_stripe -grid main_grid -layer M5 -width 0.5 -pitch 20.0 -offset 2

# Add connections
add_pdn_connect -grid main_grid -layers {M1 M4}
add_pdn_connect -grid main_grid -layers {M4 M5}
