# L=3 synthesis script
# Same basic setup as L=2, just pointing at the L=3 RTL.

set DESIGN fir_parallel_l3

analyze -format sverilog {rtl/fir_parallel_l3.sv}
elaborate $DESIGN
current_design $DESIGN
link

check_design > reports/${DESIGN}_check.rpt

create_clock -name clk -period 10 [get_ports clk]
set_input_delay 1 -clock clk [remove_from_collection [all_inputs] [get_ports {clk rst_n}]]
set_output_delay 1 -clock clk [all_outputs]
set_load 0.05 [all_outputs]

set_fix_multiple_port_nets -all -buffer_constants

compile_ultra

report_qor                 > reports/${DESIGN}_qor.rpt
report_area                > reports/${DESIGN}_area.rpt
report_timing -max_paths 5 > reports/${DESIGN}_timing.rpt
report_power               > reports/${DESIGN}_power.rpt

change_names -rules verilog -hier
write -hierarchy -format verilog -output netlist/${DESIGN}_syn.v
write -format ddc -hierarchy -output ddc/${DESIGN}.ddc

quit
