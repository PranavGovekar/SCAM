# Block-design edits for the '@APP@' application.
#
# Sourced by hw/base/scam_app.tcl with a private copy of the base design
# (base.bd) open. Every file in src/ and constraints/ has already been added to
# the project, so RTL modules can be instantiated by name:
#
#     create_bd_cell -type module -reference my_top u_my_top
#
# What the base design gives you (docs/pl-contract.md):
#     zynq_ultra_ps_e_0/pl_clk0              100 MHz, AXI clock
#     clk_wiz_0/clk_out1, clk_out2           400 MHz, 200 MHz
#     proc_sys_reset_0/peripheral_reset      active-high reset
#     axi_gpio_ctrl/gpio_io_o[1:0]           bit0 = enable, bit1 = reset
#     axi_gpio_config/gpio_io_o, gpio2_io_o  2 x 32-bit, CPU -> PL
#     axi_gpio_status/gpio_io_i              32-bit, PL -> CPU
#     axi_gpio_status2/gpio_io_i             32-bit, PL -> CPU
#     axi_gpio_flags/gpio_io_i               32-bit, PL -> CPU
#     axi_dma_0/S_AXIS_S2MM                  128-bit stream into DDR; driven by
#                                            idle_axis_source until you replace it
#
# Do not add AXI peripherals, move addresses, or change the clocks: the build
# checks this and stops. See apps/tdc/hw/bd.tcl and apps/ct/hw/bd.tcl for
# complete examples.

# Example: present a constant on the status register, so that
# 'devmem 0xA0020000 32' reads 0x5CA40001 once this bitstream is loaded.
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_id
set_property -dict [list CONFIG.CONST_WIDTH {32} CONFIG.CONST_VAL {0x5CA40001}] [get_bd_cells const_id]
connect_bd_net [get_bd_pins const_id/dout] [get_bd_pins axi_gpio_status/gpio_io_i]
