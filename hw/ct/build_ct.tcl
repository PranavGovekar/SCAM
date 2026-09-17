# =============================================================================
# Coincidence trigger application -- layers on top of the base block design.
# Prerequisite: make base-xsa
# =============================================================================

set proj_name  "scam_ct"
set bd_name    "base"
set part       "xczu9eg-ffvb1156-2-e"
set xsa_path   "../../base/base.xsa"

file delete -force ./build
file delete -force ./${proj_name}.xpr
create_project ${proj_name} ./build -part ${part} -force
set_property board_part xilinx.com:zcu102:part0:3.4 [current_project]

# Import base XSA
read_checkpoint -cell u_base ${xsa_path}

# Add CT sources
add_files -norecurse [glob ./src/*.vhd]
set_property file_type {VHDL 2008} [get_files *.vhd]

# Add constraints
add_files -fileset constrs_1 -norecurse ./constraints/ct.xdc

# Open the base BD and instantiate CT IP
set bd_file [get_files ${bd_name}.bd]
open_bd_design ${bd_file}

# Wire-up summary (to be filled in on first build):
#   1. add_files: all VHDL (above)
#   2. create_bd_cell -type module -reference ct_top u_ct_top
#   3. create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo axi_stream_tieoff
#      (or tie axi_dma_0/S_AXIS_S2MM to a constant zero stream so the DMA is idle)
#   4. Connect:
#        u_ct_top/clk_axi  <- zynq_ultra_ps_e_0/pl_clk0
#        u_ct_top/clk_fast <- clk_wiz_0/clk_out2  (200 MHz)
#        u_ct_top/rst      <- proc_sys_reset_0/peripheral_reset
#        u_ct_top/en_i     <- axi_gpio_ctrl/gpio_io_o[0]
#        u_ct_top/config   <- concat(axi_gpio_config/gpio_io_o[31:0], axi_gpio_config/gpio2_io_o[31:0])
#        u_ct_top/fifo_dout_l -> axi_gpio_status/gpio_io_i
#        u_ct_top/fifo_dout_h -> axi_gpio_status2/gpio_io_i
#        u_ct_top/fifo_flags  -> axi_gpio_flags/gpio_io_i[1:0]
#        u_ct_top/coinc_out_o -> LED bank (optional debug)
#        u_ct_top/hw_trig_o   -> LED or external pin
#   5. Tie axi_dma_0/S_AXIS_S2MM to a constant zero stream with TLAST tied low.

puts "CT BD assembly is project-specific. Fill in the block design steps"
puts "in build_ct.tcl to match your layout, then run:"
puts "   make_wrapper -top, then write_bitstream, then bootgen to .bit.bin"

# launch_runs impl_1 -to_step write_bitstream -jobs 8
# wait_on_run impl_1
# open_run impl_1
# write_bitstream -force ./bitstream/coincidence.bit
#
# bootgen -image ct.bif -arch zynqmp -o coincidence.bit.bin -w
