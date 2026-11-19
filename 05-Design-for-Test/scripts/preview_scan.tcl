set preview_report [file join [file dirname [file normalize [info script]]] scan_preview.rpt]
redirect -tee -file $preview_report {
    report_scan_configuration
    preview_dft
}
