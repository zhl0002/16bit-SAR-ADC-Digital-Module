# Archive the inserted cali_logic scan design and its test data.
set scan_export_dir [file dirname [file normalize [info script]]]
if {[get_object_name [current_design]] ne "cali_logic"} {
    error "Select cali_logic before exporting scan results."
}

set scan_post_ok 0
redirect -tee -file [file join $scan_export_dir post_scan_drc.rpt] {
    set scan_post_ok [dft_drc]
}
if {!$scan_post_ok} { error "Post-scan DFT DRC did not complete." }

set scan_path_ok 0
redirect -tee -file [file join $scan_export_dir scan_chains.rpt] {
    set scan_path_ok [report_scan_path -view existing_dft -chain all]
}
if {!$scan_path_ok} { error "Could not report the inserted scan chain." }

if {![write_file -format verilog -hierarchy -output [file join $scan_export_dir cali_logic_scan.v]]} {
    error "Could not export the scan netlist."
}
if {![write_test_protocol -output [file join $scan_export_dir cali_logic_scan.spf]]} {
    error "Could not export the STIL test protocol."
}
if {![write_scan_def -output [file join $scan_export_dir cali_logic_scan.def]]} {
    error "Could not export SCANDEF."
}
puts "DFT_EXPORT_COMPLETE: $scan_export_dir"
