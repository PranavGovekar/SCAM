# Coincidence-trigger block-design edits, sourced by hw/base/scam_app.tcl with
# base.bd open. The RTL in src/ and the constraints in constraints/ are already
# added.

create_bd_cell -type module -reference ct_top u_ct_top

create_bd_port -dir I -from 3 -to 0 -type data diff_in_p
create_bd_port -dir I -from 3 -to 0 -type data diff_in_n
create_bd_port -dir O -from 4 -to 0 -type data oe
create_bd_port -dir O -from 4 -to 0 -type data term

connect_bd_net [get_bd_ports diff_in_p] [get_bd_pins u_ct_top/diff_in_p]
connect_bd_net [get_bd_ports diff_in_n] [get_bd_pins u_ct_top/diff_in_n]

create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_io_enable
set_property -dict [list CONFIG.CONST_WIDTH {5} CONFIG.CONST_VAL {31}] [get_bd_cells const_io_enable]
connect_bd_net [get_bd_pins const_io_enable/dout] [get_bd_ports oe]
connect_bd_net [get_bd_pins const_io_enable/dout] [get_bd_ports term]

create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 slice_enable
set_property -dict [list CONFIG.DIN_WIDTH {2} CONFIG.DIN_FROM {0} CONFIG.DIN_TO {0} CONFIG.DOUT_WIDTH {1}] [get_bd_cells slice_enable]
connect_bd_net [get_bd_pins axi_gpio_ctrl/gpio_io_o] [get_bd_pins slice_enable/Din]
connect_bd_net [get_bd_pins slice_enable/Dout] [get_bd_pins u_ct_top/en_i]

create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 concat_config
set_property CONFIG.NUM_PORTS {2} [get_bd_cells concat_config]
connect_bd_net [get_bd_pins axi_gpio_config/gpio_io_o] [get_bd_pins concat_config/In0]
connect_bd_net [get_bd_pins axi_gpio_config/gpio2_io_o] [get_bd_pins concat_config/In1]
connect_bd_net [get_bd_pins concat_config/dout] [get_bd_pins u_ct_top/config_i]

connect_bd_net [get_bd_pins u_ct_top/fifo_dout_l] [get_bd_pins axi_gpio_status/gpio_io_i]
connect_bd_net [get_bd_pins u_ct_top/fifo_dout_h] [get_bd_pins axi_gpio_status2/gpio_io_i]
connect_bd_net [get_bd_pins u_ct_top/fifo_flags] [get_bd_pins axi_gpio_flags/gpio_io_i]

connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] [get_bd_pins u_ct_top/clk_axi]
connect_bd_net [get_bd_pins clk_wiz_0/clk_out2] [get_bd_pins u_ct_top/clk_fast]
connect_bd_net [get_bd_pins proc_sys_reset_0/peripheral_reset] [get_bd_pins u_ct_top/rst]

# CT events are read through the fixed GPIO contract. The base's zero stream
# tie-offs remain connected to the DMA S2MM input.
