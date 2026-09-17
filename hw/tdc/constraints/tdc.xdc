# TDC pin assignments.
# Adjust to match your FMC / SMA mapping.
#
# Placeholder -- replace with your actual pinout.

# Example: two differential pairs on FMC HPC0
# set_property PACKAGE_PIN G2 [get_ports diff_in_p_0]
# set_property IOSTANDARD LVDS [get_ports diff_in_p_0]
# set_property PACKAGE_PIN G1 [get_ports diff_in_n_0]
# set_property IOSTANDARD LVDS [get_ports diff_in_n_0]
#
# set_property PACKAGE_PIN J4 [get_ports diff_in_p_1]
# set_property IOSTANDARD LVDS [get_ports diff_in_p_1]
# set_property PACKAGE_PIN J3 [get_ports diff_in_n_1]
# set_property IOSTANDARD LVDS [get_ports diff_in_n_1]

# LED mapping (LED_0 heartbeat, LED_4[4:0] chase)
# set_property PACKAGE_PIN AG14 [get_ports led_0]
# set_property IOSTANDARD LVCMOS18 [get_ports led_0]
# set_property PACKAGE_PIN AF13 [get_ports led_1]
# set_property IOSTANDARD LVCMOS18 [get_ports led_1]
# for {set i 0} {$i < 5} {incr i} {
#     set_property PACKAGE_PIN ... [get_ports "led_4[$i]"]
#     set_property IOSTANDARD LVCMOS18 [get_ports "led_4[$i]"]
# }
