###################################################################

# Created by write_sdc on Wed Nov 18 00:51:24 2026

###################################################################
set sdc_version 2.1

set_units -time ns -resistance kOhm -capacitance pF -voltage V -current mA
create_clock [get_ports clk_i]  -name cal_clk  -period 10  -waveform {0 5}
