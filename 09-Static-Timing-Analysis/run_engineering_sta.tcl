# Replay cali_logic engineering STA in a fresh PrimeTime session.
# Source this file from the directory where the reports should be written.

foreach name {STA_LIB STA_NETLIST STA_SPEF} {
    if {![info exists ::env($name)] || ![file readable $::env($name)] || ![file isfile $::env($name)]} {
        error "Set $name to the corresponding readable local input file"
    }
}

set constraints [file join [file dirname [file normalize [info script]]] constraints cali_logic_compact_10ns.sdc]
set_app_var link_path [list * $::env(STA_LIB)]
if {![read_db $::env(STA_LIB)]} { error "Cannot read the timing library" }
if {![read_verilog $::env(STA_NETLIST)]} { error "Cannot read the routed netlist" }
if {[link_design -verbose cali_logic] ne "1"} { error "Cannot link cali_logic" }
if {![read_sdc -echo $constraints]} { error "Cannot read timing constraints" }
if {![read_parasitics -format SPEF $::env(STA_SPEF)]} { error "Cannot read parasitics" }

redirect -file parasitics_coverage.rpt {
    report_annotated_parasitics -check
}
redirect -file check_timing.rpt {check_timing -verbose}
redirect -file clocks.rpt {report_clock -attributes}
redirect -file timing_summary.rpt {
    report_global_timing -group cal_clk -significant_digits 4
}
redirect -file setup_reg_to_reg.rpt {
    report_timing -delay_type max -start_end_type reg_to_reg -max_paths 1 -path_type full_clock_expanded -significant_digits 4
}
redirect -file hold_reg_to_reg.rpt {
    report_timing -delay_type min -start_end_type reg_to_reg -max_paths 1 -path_type full_clock_expanded -significant_digits 4
}
