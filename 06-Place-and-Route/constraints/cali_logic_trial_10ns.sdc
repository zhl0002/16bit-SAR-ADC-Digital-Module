# Functional-mode trial constraints for the standalone cali_logic block.
# Load into the active functional/typical scenario, whose library uses ns.
# The 10 ns period is an implementation trial value.
create_clock -name cal_clk -period 10 -waveform {0 5} [get_ports clk_i]
set_case_analysis 0 [get_ports scan_en]
