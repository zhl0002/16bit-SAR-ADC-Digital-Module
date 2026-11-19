# Insert the previewed chain in the active cali_logic design.
set scan_run [file dirname [file normalize [info script]]]
if {[get_object_name [current_design]] ne "cali_logic"} {
    error "Select cali_logic before scan insertion."
}
set scan_insert_report [file join $scan_run scan_insert.rpt]
set scan_insert_svf [file join $scan_run cali_logic_scan.svf]
if {[file exists $scan_insert_report] || [file exists $scan_insert_svf]} {
    error "This run already has scan insertion output. Review the existing report."
}

set scan_insert_ok 0
set_svf $scan_insert_svf
set scan_insert_failed [catch {
    redirect -tee -file $scan_insert_report {
        set scan_insert_ok [insert_dft]
    }
} scan_insert_message]
set_svf -off
if {$scan_insert_failed} { error $scan_insert_message }
if {!$scan_insert_ok} { error "Scan insertion failed. See $scan_insert_report." }

set scan_checkpoint [file join $scan_run cali_logic_scan.ddc]
if {![write_file -format ddc -hierarchy -output $scan_checkpoint]} {
    error "Scan inserted, but the checkpoint could not be saved."
}
puts "SCAN_INSERT_COMPLETE: $scan_checkpoint"
