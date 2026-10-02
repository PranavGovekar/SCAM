# FMC DIO 5ch on ZCU102 HPC0. This CT design uses channels 0 through 3.
# Differential input pair pin assignments are from the supplied board mapping.

# Channel 0 — HPC0 LA33, Bank 65
set_property PACKAGE_PIN V12 [get_ports {diff_in_p[0]}]
set_property PACKAGE_PIN V11 [get_ports {diff_in_n[0]}]
set_property IOSTANDARD LVDS [get_ports {diff_in_p[0]}]
set_property IOSTANDARD LVDS [get_ports {diff_in_n[0]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {diff_in_p[0]}]

# Channel 1 — HPC0 LA20, Bank 66
set_property PACKAGE_PIN N13 [get_ports {diff_in_p[1]}]
set_property PACKAGE_PIN M13 [get_ports {diff_in_n[1]}]
set_property IOSTANDARD LVDS [get_ports {diff_in_p[1]}]
set_property IOSTANDARD LVDS [get_ports {diff_in_n[1]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {diff_in_p[1]}]

# Channel 2 — HPC0 LA16, Bank 66
set_property PACKAGE_PIN Y12 [get_ports {diff_in_p[2]}]
set_property PACKAGE_PIN AA12 [get_ports {diff_in_n[2]}]
set_property IOSTANDARD LVDS [get_ports {diff_in_p[2]}]
set_property IOSTANDARD LVDS [get_ports {diff_in_n[2]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {diff_in_p[2]}]

# Channel 3 — HPC0 LA03, Bank 65
set_property PACKAGE_PIN Y2 [get_ports {diff_in_p[3]}]
set_property PACKAGE_PIN Y1 [get_ports {diff_in_n[3]}]
set_property IOSTANDARD LVDS [get_ports {diff_in_p[3]}]
set_property IOSTANDARD LVDS [get_ports {diff_in_n[3]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {diff_in_p[3]}]

# FMC DIO direction and termination controls for the five HPC0 channels.
set_property PACKAGE_PIN V6 [get_ports {oe[0]}]
set_property PACKAGE_PIN K12 [get_ports {oe[1]}]
set_property PACKAGE_PIN Y9 [get_ports {oe[2]}]
set_property PACKAGE_PIN AB6 [get_ports {oe[3]}]
set_property PACKAGE_PIN AB3 [get_ports {oe[4]}]
set_property IOSTANDARD LVCMOS18 [get_ports {oe[*]}]

set_property PACKAGE_PIN U6 [get_ports {term[0]}]
set_property PACKAGE_PIN AC1 [get_ports {term[1]}]
set_property PACKAGE_PIN AC3 [get_ports {term[2]}]
set_property PACKAGE_PIN W2 [get_ports {term[3]}]
set_property PACKAGE_PIN W1 [get_ports {term[4]}]
set_property IOSTANDARD LVCMOS18 [get_ports {term[*]}]

# The CT configuration GPIO and trigger logic use the PS PL0 and the
# clock-wizard 200 MHz clocks.  The clock-wizard input timing model is
# 10.001 ns while the PS model is 10.000 ns, so Vivado cannot expand a common
# clock period between them.  Keep the cross-domain datapaths bounded using
# the same 10 ns policy as the previously working TDC constraints; do not
# mark these paths false because config and FIFO data are real signals.
set clk_sys  [get_clocks -quiet clk_pl_0]
set clk_fast [get_clocks -quiet clk_out2_base_clk_wiz_0_0]
set_max_delay -datapath_only -from $clk_sys  -to $clk_fast 10.0
set_max_delay -datapath_only -from $clk_fast -to $clk_sys  10.0
