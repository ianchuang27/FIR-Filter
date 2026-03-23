# Baseline synthesis script
# Keep this one simple so it stays the reference case.

set DESIGN fir_baseline

# Read and elaborate the RTL
analyze -format sverilog {rtl/fir_baseline.sv}
elaborate $DESIGN
current_design $DESIGN
link

# Saves a design-check report before compiling
check_design > reports/${DESIGN}_check.rpt

# Main timing/load assumptions used for comparison across architectures
create_clock -name clk -period 10 [get_ports clk]
set_input_delay 1 -clock clk [remove_from_collection [all_inputs] [get_ports {clk rst_n}]]
set_output_delay 1 -clock clk [all_outputs]
set_load 0.05 [all_outputs]

# Clean up multiple-port nets and constants before compile
set_fix_multiple_port_nets -all -buffer_constants

compile

# Save reports used in the comparison table
report_qor                 > reports/${DESIGN}_qor.rpt
report_area                > reports/${DESIGN}_area.rpt
report_timing -max_paths 5 > reports/${DESIGN}_timing.rpt
report_power               > reports/${DESIGN}_power.rpt

# Rename objects into cleaner Verilog names before writing the netlist
change_names -rules verilog -hier
write -hierarchy -format verilog -output netlist/${DESIGN}_syn.v
write -format ddc -hierarchy -output ddc/${DESIGN}.ddc

quit
