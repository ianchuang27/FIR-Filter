set DESIGN fir_pipelined_v2

set_host_options -max_cores 8

analyze -format sverilog [list rtl/${DESIGN}.sv]
elaborate $DESIGN
current_design $DESIGN
link

check_design > reports/${DESIGN}_check.rpt

set_fix_multiple_port_nets -all -buffer_constants [current_design]

create_clock -name clk -period 10 [get_ports clk]
set_clock_uncertainty 0.2 [get_clocks clk]

set_input_delay 1 -clock clk [remove_from_collection [all_inputs] [get_ports clk]]
set_output_delay 1 -clock clk [all_outputs]
set_load 0.05 [all_outputs]

compile_ultra

change_names -rules verilog -hierarchy
update_timing

report_constraint -all_violators > reports/${DESIGN}_constraints.rpt
report_area   > reports/${DESIGN}_area.rpt
report_timing -max_paths 10 -nworst 1 > reports/${DESIGN}_timing.rpt
report_power  > reports/${DESIGN}_power.rpt
report_qor    > reports/${DESIGN}_qor.rpt

write -hierarchy -format verilog -output netlist/${DESIGN}_syn.v
write -format ddc -hierarchy -output ddc/${DESIGN}.ddc

quit
