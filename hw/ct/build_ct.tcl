# Build the coincidence-trigger application from the reusable base design.
# Run from any directory with: vivado -mode batch -source <this file>

set app_dir [file dirname [file normalize [info script]]]
set base_script [file normalize [file join $app_dir .. base build_base_xsa.tcl]]
set base_project_dir [file join $app_dir .. base build scam_base_project]
set base_project_xpr [file join $base_project_dir scam_base.xpr]
set proj_name scam_ct
set build_dir [file normalize [expr {[info exists ::env(SCAM_BUILD_DIR)] ? $::env(SCAM_BUILD_DIR) : [file join $app_dir build ${proj_name}_project]}]]
set ::SCAM_APP_PROJECT_NAME $proj_name
set ::SCAM_APP_BUILD_DIR $build_dir

# Clone the editable base template through Vivado so generated IP paths remain
# valid and user changes saved in the template are inherited by this app.
if {![file exists $base_project_xpr]} {
    set had_build_override [info exists ::env(SCAM_BUILD_DIR)]
    if {$had_build_override} {
        set requested_build_dir $::env(SCAM_BUILD_DIR)
        unset ::env(SCAM_BUILD_DIR)
    }
    set ::SCAM_TEMPLATE_ONLY 1
    source $base_script
    unset ::SCAM_TEMPLATE_ONLY
    close_project
    if {$had_build_override} {
        set ::env(SCAM_BUILD_DIR) $requested_build_dir
    }
}
open_project $base_project_xpr
save_project_as -force -exclude_run_results $::SCAM_APP_PROJECT_NAME $::SCAM_APP_BUILD_DIR
close_project
open_project [file join $::SCAM_APP_BUILD_DIR ${::SCAM_APP_PROJECT_NAME}.xpr]
set build_dir $::SCAM_APP_BUILD_DIR

set vhd_files [glob -nocomplain [file join $app_dir src *.vhd]]
if {[llength $vhd_files] == 0} {
    error "No CT VHDL sources found under [file join $app_dir src]"
}
add_files -norecurse $vhd_files
set_property file_type VHDL [get_files $vhd_files]
update_compile_order -fileset sources_1
add_files -fileset constrs_1 -norecurse [file join $app_dir constraints ct.xdc]

open_bd_design [get_files base.bd]
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
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_flags_zero
set_property -dict [list CONFIG.CONST_WIDTH {30} CONFIG.CONST_VAL {0}] [get_bd_cells const_flags_zero]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 concat_flags
set_property CONFIG.NUM_PORTS {2} [get_bd_cells concat_flags]
connect_bd_net [get_bd_pins u_ct_top/fifo_flags] [get_bd_pins concat_flags/In0]
connect_bd_net [get_bd_pins const_flags_zero/dout] [get_bd_pins concat_flags/In1]
connect_bd_net [get_bd_pins concat_flags/dout] [get_bd_pins axi_gpio_flags/gpio_io_i]

connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] [get_bd_pins u_ct_top/clk_axi]
connect_bd_net [get_bd_pins clk_wiz_0/clk_out2] [get_bd_pins u_ct_top/clk_fast]
connect_bd_net [get_bd_pins proc_sys_reset_0/peripheral_reset] [get_bd_pins u_ct_top/rst]

# CT events are read through the fixed GPIO contract. The base's zero stream
# tie-offs remain connected to the DMA S2MM input.
regenerate_bd_layout
validate_bd_design
save_bd_design
make_wrapper -files [get_files base.bd] -top -force
set_property top base_wrapper [current_fileset]
update_compile_order -fileset sources_1

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
open_run impl_1
set bitstream_dir [file normalize [expr {[info exists ::env(SCAM_BITSTREAM_DIR)] ? $::env(SCAM_BITSTREAM_DIR) : [file join $app_dir bitstream]}]]
file mkdir $bitstream_dir
write_bitstream -force [file join $bitstream_dir coincidence.bit]
puts "CT bitstream written to [file join $bitstream_dir coincidence.bit]"
