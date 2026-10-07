# TDC block-design edits, sourced by hw/base/scam_app.tcl with base.bd open.
# The RTL in src/ and the constraints in constraints/ are already added.

# Replace the base design's idle AXI4-Stream master with the TDC master.
delete_bd_objs [get_bd_cells idle_axis_source]

create_bd_cell -type module -reference tdc_top u_tdc_top
create_bd_cell -type module -reference diff_to_se_1ch u_diff_ch0
create_bd_cell -type module -reference diff_to_se_1ch u_diff_ch1
create_bd_cell -type module -reference se_to_diff_1ch u_diff_out_0
create_bd_cell -type module -reference se_to_diff_1ch u_diff_out_1
create_bd_cell -type module -reference heartbeat_led u_hb_led
create_bd_cell -type module -reference led_controller u_led_ctrl

foreach name {diff_in_p_0 diff_in_n_0 diff_in_p_1 diff_in_n_1} {
    create_bd_port -dir I -type data $name
}
foreach name {diff_out_p_0 diff_out_n_0 diff_out_p_1 diff_out_n_1 led_0 led_1 led_2 led_3} {
    create_bd_port -dir O -type data $name
}
create_bd_port -dir O -from 4 -to 0 oe
create_bd_port -dir O -from 4 -to 0 term

connect_bd_net [get_bd_ports diff_in_p_0] [get_bd_pins u_diff_ch0/diff_in_p]
connect_bd_net [get_bd_ports diff_in_n_0] [get_bd_pins u_diff_ch0/diff_in_n]
connect_bd_net [get_bd_ports diff_in_p_1] [get_bd_pins u_diff_ch1/diff_in_p]
connect_bd_net [get_bd_ports diff_in_n_1] [get_bd_pins u_diff_ch1/diff_in_n]

create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 xlconcat_hits
set_property CONFIG.NUM_PORTS {2} [get_bd_cells xlconcat_hits]
connect_bd_net [get_bd_pins u_diff_ch0/se_out] [get_bd_pins xlconcat_hits/In0]
connect_bd_net [get_bd_pins u_diff_ch1/se_out] [get_bd_pins xlconcat_hits/In1]
connect_bd_net [get_bd_pins xlconcat_hits/dout] [get_bd_pins u_tdc_top/hit_i]

create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_gnd
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {0}] [get_bd_cells const_gnd]
foreach pin {u_diff_out_0/se_in u_diff_out_1/se_in u_hb_led/rst} {
    connect_bd_net [get_bd_pins const_gnd/dout] [get_bd_pins $pin]
}
foreach {cell pin port} {
    u_diff_out_0 diff_out_p diff_out_p_0
    u_diff_out_0 diff_out_n diff_out_n_0
    u_diff_out_1 diff_out_p diff_out_p_1
    u_diff_out_1 diff_out_n diff_out_n_1
} {
    connect_bd_net [get_bd_pins $cell/$pin] [get_bd_ports $port]
}

create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_io_enable
set_property -dict [list CONFIG.CONST_WIDTH {5} CONFIG.CONST_VAL {31}] [get_bd_cells const_io_enable]
connect_bd_net [get_bd_pins const_io_enable/dout] [get_bd_ports oe]
connect_bd_net [get_bd_pins const_io_enable/dout] [get_bd_ports term]

create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_led_enable
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {1}] [get_bd_cells const_led_enable]
connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] [get_bd_pins u_hb_led/clk]
connect_bd_net [get_bd_pins u_hb_led/led] [get_bd_ports led_0]
connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] [get_bd_pins u_led_ctrl/clk]
connect_bd_net [get_bd_pins const_led_enable/dout] [get_bd_pins u_led_ctrl/enable]
foreach {idx port} {1 led_1 2 led_2 3 led_3} {
    create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 slice_led$idx
    set_property -dict [list CONFIG.DIN_WIDTH {5} CONFIG.DIN_FROM $idx CONFIG.DIN_TO $idx CONFIG.DOUT_WIDTH {1}] [get_bd_cells slice_led$idx]
    connect_bd_net [get_bd_pins u_led_ctrl/led] [get_bd_pins slice_led$idx/Din]
    connect_bd_net [get_bd_pins slice_led$idx/Dout] [get_bd_ports $port]
}

connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins u_tdc_top/clk_fast_i]
connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] [get_bd_pins u_tdc_top/clk_sys_i]
connect_bd_net [get_bd_pins proc_sys_reset_0/peripheral_reset] [get_bd_pins u_tdc_top/rst_i]

create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 slice_enable
set_property -dict [list CONFIG.DIN_WIDTH {2} CONFIG.DIN_FROM {0} CONFIG.DIN_TO {0} CONFIG.DOUT_WIDTH {1}] [get_bd_cells slice_enable]
connect_bd_net [get_bd_pins axi_gpio_ctrl/gpio_io_o] [get_bd_pins slice_enable/Din]
connect_bd_net [get_bd_pins slice_enable/Dout] [get_bd_pins u_tdc_top/en_i]
connect_bd_net [get_bd_pins u_tdc_top/fifo_overflow_count_o] [get_bd_pins axi_gpio_status/gpio_io_i]
connect_bd_intf_net [get_bd_intf_pins u_tdc_top/M_AXIS] [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]
