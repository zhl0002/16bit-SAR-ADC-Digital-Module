################################################################################
#
# Design name:  cali_logic
#
# Created by icc2 write_sdc on Sun Nov 22 20:14:30 2026
#
################################################################################

set sdc_version 2.1
set_units -time ns -resistance kOhm -capacitance pF -voltage V -current mA

################################################################################
#
# Units
# time_unit               : 1e-09
# resistance_unit         : 1000
# capacitive_load_unit    : 1e-12
# voltage_unit            : 1
# current_unit            : 0.001
# power_unit              : 1e-12
################################################################################


# Mode: func_trial
# Corner: typ_trial
# Scenario: func_typ_trial

set_case_analysis 0 [get_ports {scan_en}]
create_clock -name cal_clk -period 10 -waveform {0 5} [get_ports {clk_i}]
set_propagated_clock [get_clocks {cal_clk}]
# Warning: Libcell power domain derates are skipped!

# Set latency for io paths.
# -origin user
set_clock_latency 0.269508 [get_clocks {cal_clk}]
# Set propagated on clock sources to avoid removing latency for IO paths.
set_propagated_clock  [get_ports {clk_i}]
set_clock_uncertainty 0 [get_clocks {cal_clk}]
