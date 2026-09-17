# =============================================================================
# TDC application -- layers on top of the base block design.
# Prerequisite: make base-xsa
# =============================================================================

set proj_name  "scam_tdc"
set bd_name    "base"
set part       "xczu9eg-ffvb1156-2-e"
set xsa_path   "../../base/base.xsa"

file delete -force ./build
file delete -force ./${proj_name}.xpr
create_project ${proj_name} ./build -part ${part} -force
set_property board_part xilinx.com:zcu102:part0:3.4 [current_project]

# Import base XSA
read_checkpoint -cell u_base ${xsa_path}

# Add TDC sources
add_files -norecurse [glob ./src/*.vhd]
set_property file_type {VHDL 2008} [get_files *.vhd]

# Add constraints
add_files -fileset constrs_1 -norecurse ./constraints/tdc.xdc

# Open the imported base BD and instantiate TDC IP into it.
set bd_file [get_files ${bd_name}.bd]
open_bd_design ${bd_file}

# NOTE: this section assumes you have already run the base XSA generation and
# that the base BD is saved inside the XSA. The commands below are illustrative
# and must be adjusted to match how you want to wire the TDC into the base.
# The typical pattern:
#   1. add_files -norecurse all VHDL
#   2. create_bd_cell for each IP (or use module_ref)
#   3. wire diff_in_* into diff_to_se_1ch -> hit_concat -> tdc_top
#   4. tdc_top.m_axis -> axis_data_fifo -> axi_dma_0/S_AXIS_S2MM
#   5. tdc_top.fifo_overflow_count_o -> axi_gpio_status/gpio_io_i
#   6. axi_gpio_ctrl/gpio_io_o(0) -> tdc_top/en_i
#   7. axi_gpio_ctrl/gpio_io_o(1) -> proc_sys_reset_0/ext_reset_in

puts "TDC BD assembly is project-specific. Fill in the block design steps"
puts "in build_tdc.tcl to match your layout, then run:"
puts "   make_wrapper -top, then write_bitstream, then bootgen to .bit.bin"

# Bitstream generation (uncomment after the BD is complete):
# launch_runs impl_1 -to_step write_bitstream -jobs 8
# wait_on_run impl_1
# open_run impl_1
# write_bitstream -force ./bitstream/tdc.bit
#
# Then on host:
#   echo "all:{tdc.bit}" > tdc.bif
#   bootgen -image tdc.bif -arch zynqmp -o tdc.bit.bin -w
