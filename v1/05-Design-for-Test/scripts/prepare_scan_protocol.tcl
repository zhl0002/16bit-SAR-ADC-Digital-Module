# Prepare scan pins and the test protocol in the current cali_logic session.
if {[get_object_name [current_design]] ne "cali_logic"} {
    error "Select cali_logic as the current design before running this script."
}

foreach {port_name direction} {scan_in in scan_en in scan_out out} {
    set port [get_ports -quiet $port_name]
    if {[sizeof_collection $port] == 0} {
        create_port -direction $direction $port_name
    } elseif {[get_attribute $port direction] ne $direction} {
        error "Port $port_name must have direction $direction."
    }
}

set_dft_signal -view spec -type ScanDataIn -port scan_in
set_dft_signal -view spec -type ScanDataOut -port scan_out
set_dft_signal -view spec -type ScanEnable -port scan_en -active_state 1
set_scan_path scan_chain_0 -view spec -scan_data_in scan_in -scan_data_out scan_out -scan_enable scan_en

create_test_protocol
report_dft_signal -view spec
