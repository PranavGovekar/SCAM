# =============================================================================
# SCAM base block design
# Produces system.xsa for PetaLinux.
# Run: vivado -mode batch -source build_base_xsa.tcl
# =============================================================================

set script_dir [file dirname [file normalize [info script]]]
set template_only [expr {[info exists ::SCAM_TEMPLATE_ONLY] && $::SCAM_TEMPLATE_ONLY}]
set proj_name "scam_base"
set bd_name    "base"
set part       "xczu9eg-ffvb1156-2-e"
set build_dir  [file normalize [expr {[info exists ::env(SCAM_BUILD_DIR)] ? $::env(SCAM_BUILD_DIR) : [file join $script_dir build ${proj_name}_project]}]]
set project_file [file join $build_dir ${proj_name}.xpr]
set project_exists [file exists $project_file]
if {[info exists ::env(SCAM_REBUILD_TEMPLATE)] && $::env(SCAM_REBUILD_TEMPLATE)} {
    set project_exists 0
}

if {!$project_exists} {
    # Create the editable template only when one is not already present. This
    # preserves changes made in the Vivado GUI when users rebuild the XSA.
    file delete -force $build_dir

    create_project ${proj_name} $build_dir -part ${part} -force

    set_property board_part xilinx.com:zcu102:part0:3.4 [current_project]
    set idle_source [file join $script_dir src axis_idle_source.vhd]
    add_files -norecurse $idle_source
    set_property file_type VHDL [get_files $idle_source]
    update_compile_order -fileset sources_1

# -----------------------------------------------------------------------------
# Block design
# -----------------------------------------------------------------------------
create_bd_design ${bd_name}
current_bd_design ${bd_name}

# -- Zynq PS ------------------------------------------------------------------
create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.5 zynq_ultra_ps_e_0
set ps [get_bd_cells zynq_ultra_ps_e_0]

# Apply preset then trim
apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e     -config {apply_board_preset "1"} [get_bd_cells zynq_ultra_ps_e_0]

# Core PS settings we rely on. The board preset already enables most of these;
# we lock in the essential ones and disable what we don't want.
set_property -dict [list \
    CONFIG.PSU__USE__M_AXI_GP0 {1} \
    CONFIG.PSU__USE__M_AXI_GP1 {0} \
    CONFIG.PSU__USE__S_AXI_GP0 {0} \
    CONFIG.PSU__USE__S_AXI_GP1 {0} \
    CONFIG.PSU__USE__S_AXI_GP2 {1} \
    CONFIG.PSU__USE__IRQ0 {1} \
    CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100} \
    CONFIG.PSU__FPGA_PL0_ENABLE {1} \
    CONFIG.PSU__I2C0__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__I2C1__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__I2C1__PERIPHERAL__IO {MIO 16 .. 17} \
    CONFIG.PSU__QSPI__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__QSPI__PERIPHERAL__MODE {Dual Parallel} \
    CONFIG.PSU__QSPI__PERIPHERAL__DATA_MODE {x4} \
    CONFIG.PSU__SD1__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__SD1__PERIPHERAL__IO {MIO 39 .. 51} \
    CONFIG.PSU__UART0__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__UART0__PERIPHERAL__IO {MIO 18 .. 19} \
    CONFIG.PSU__ENET3__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__ENET3__PERIPHERAL__IO {MIO 64 .. 75} \
    CONFIG.PSU__ENET3__GRP_MDIO__ENABLE {1} \
    CONFIG.PSU__ENET3__GRP_MDIO__IO {MIO 76 .. 77} \
    CONFIG.PSU__GPIO0_MIO__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__GPIO1_MIO__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__USB0__PERIPHERAL__ENABLE {0} \
    CONFIG.PSU__USB3_0__PERIPHERAL__ENABLE {0} \
    CONFIG.PSU__DISPLAYPORT__PERIPHERAL__ENABLE {0} \
    CONFIG.PSU__PCIE__PERIPHERAL__ENABLE {0} \
    CONFIG.PSU__SATA__PERIPHERAL__ENABLE {0} \
] $ps

# -- Clocking -----------------------------------------------------------------
# clk_wiz_0: 100 MHz in, 400 MHz + 200 MHz out
create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz_0
set_property -dict [list \
    CONFIG.PRIM_IN_FREQ {100.000} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {400.000} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {200.000} \
    CONFIG.CLKOUT2_USED {true} \
    CONFIG.USE_LOCKED {false} \
    CONFIG.USE_RESET {false} \
] [get_bd_cells clk_wiz_0]

# -- Proc sys reset -----------------------------------------------------------
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_0

# -- AXI interconnect ---------------------------------------------------------
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 ps8_0_axi_periph
set_property -dict [list CONFIG.NUM_MI {6}] [get_bd_cells ps8_0_axi_periph]

# -- AXI DMA (S2MM only) ------------------------------------------------------
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_0
set_property -dict [list \
    CONFIG.c_include_sg {0} \
    CONFIG.c_sg_include_stscntrl_strm {0} \
    CONFIG.c_include_mm2s {0} \
    CONFIG.c_include_s2mm {1} \
    CONFIG.c_s2mm_burst_size {256} \
    CONFIG.c_s_axis_s2mm_tdata_width {128} \
    CONFIG.c_m_axi_s2mm_data_width {128} \
    CONFIG.c_addr_width {40} \
] [get_bd_cells axi_dma_0]
create_bd_cell -type module -reference axis_idle_source idle_axis_source

# -- AXI GPIOs ----------------------------------------------------------------
# Control: 2-bit output
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_ctrl
set_property -dict [list \
    CONFIG.C_GPIO_WIDTH {2} \
    CONFIG.C_ALL_OUTPUTS {1} \
    CONFIG.C_IS_DUAL {0} \
] [get_bd_cells axi_gpio_ctrl]

# Status: 32-bit input
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_status
set_property -dict [list \
    CONFIG.C_GPIO_WIDTH {32} \
    CONFIG.C_ALL_INPUTS {1} \
    CONFIG.C_IS_DUAL {0} \
] [get_bd_cells axi_gpio_status]

# Config: dual channel, 32-bit each, output
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_config
set_property -dict [list \
    CONFIG.C_GPIO_WIDTH {32} \
    CONFIG.C_GPIO2_WIDTH {32} \
    CONFIG.C_IS_DUAL {1} \
    CONFIG.C_ALL_OUTPUTS {1} \
    CONFIG.C_ALL_OUTPUTS_2 {1} \
] [get_bd_cells axi_gpio_config]

# Status2: 32-bit input
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_status2
set_property -dict [list \
    CONFIG.C_GPIO_WIDTH {32} \
    CONFIG.C_ALL_INPUTS {1} \
    CONFIG.C_IS_DUAL {0} \
] [get_bd_cells axi_gpio_status2]

# Flags: 32-bit input
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_flags
set_property -dict [list \
    CONFIG.C_GPIO_WIDTH {32} \
    CONFIG.C_ALL_INPUTS {1} \
    CONFIG.C_IS_DUAL {0} \
] [get_bd_cells axi_gpio_flags]

# -----------------------------------------------------------------------------
# Connections
# -----------------------------------------------------------------------------
# Clocks
connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] \
    [get_bd_pins ps8_0_axi_periph/ACLK] \
    [get_bd_pins ps8_0_axi_periph/S00_ACLK] \
    [get_bd_pins ps8_0_axi_periph/M00_ACLK] \
    [get_bd_pins ps8_0_axi_periph/M01_ACLK] \
    [get_bd_pins ps8_0_axi_periph/M02_ACLK] \
    [get_bd_pins ps8_0_axi_periph/M03_ACLK] \
    [get_bd_pins ps8_0_axi_periph/M04_ACLK] \
    [get_bd_pins ps8_0_axi_periph/M05_ACLK] \
    [get_bd_pins axi_dma_0/s_axi_lite_aclk] \
    [get_bd_pins axi_dma_0/m_axi_s2mm_aclk] \
    [get_bd_pins axi_gpio_ctrl/s_axi_aclk] \
    [get_bd_pins axi_gpio_status/s_axi_aclk] \
    [get_bd_pins axi_gpio_config/s_axi_aclk] \
    [get_bd_pins axi_gpio_status2/s_axi_aclk] \
    [get_bd_pins axi_gpio_flags/s_axi_aclk] \
    [get_bd_pins clk_wiz_0/clk_in1] \
    [get_bd_pins zynq_ultra_ps_e_0/maxihpm0_fpd_aclk] \
    [get_bd_pins zynq_ultra_ps_e_0/saxihp0_fpd_aclk]
connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] \
    [get_bd_pins idle_axis_source/aclk]

# Set the clock wizard input frequency from the configured PS clock.
set freq_hz [get_property CONFIG.FREQ_HZ [get_bd_pins zynq_ultra_ps_e_0/pl_clk0]]
set_property CONFIG.PRIM_IN_FREQ [expr {$freq_hz / 1000000.0}] [get_bd_cells clk_wiz_0]

connect_bd_intf_net [get_bd_intf_pins idle_axis_source/M_AXIS] \
    [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]

# Control GPIO bit 1 is active-low reset release. Combine it with the PS reset
# so software can reset application logic using the fixed PL contract.
create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 slice_ctrl_reset_n
set_property -dict [list CONFIG.DIN_WIDTH {2} CONFIG.DIN_FROM {1} CONFIG.DIN_TO {1} CONFIG.DOUT_WIDTH {1}] [get_bd_cells slice_ctrl_reset_n]
connect_bd_net [get_bd_pins axi_gpio_ctrl/gpio_io_o] [get_bd_pins slice_ctrl_reset_n/Din]
create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 reset_n_and
set_property -dict [list CONFIG.C_OPERATION {and} CONFIG.C_SIZE {1}] [get_bd_cells reset_n_and]
connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_resetn0] [get_bd_pins reset_n_and/Op1]
connect_bd_net [get_bd_pins slice_ctrl_reset_n/Dout] [get_bd_pins reset_n_and/Op2]
connect_bd_net [get_bd_pins reset_n_and/Res] [get_bd_pins proc_sys_reset_0/ext_reset_in]
connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] \
    [get_bd_pins proc_sys_reset_0/slowest_sync_clk]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_dcm_locked
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {1}] [get_bd_cells const_dcm_locked]
connect_bd_net [get_bd_pins const_dcm_locked/dout] [get_bd_pins proc_sys_reset_0/dcm_locked]
connect_bd_net [get_bd_pins proc_sys_reset_0/peripheral_aresetn] \
    [get_bd_pins ps8_0_axi_periph/ARESETN] \
    [get_bd_pins ps8_0_axi_periph/S00_ARESETN] \
    [get_bd_pins ps8_0_axi_periph/M00_ARESETN] \
    [get_bd_pins ps8_0_axi_periph/M01_ARESETN] \
    [get_bd_pins ps8_0_axi_periph/M02_ARESETN] \
    [get_bd_pins ps8_0_axi_periph/M03_ARESETN] \
    [get_bd_pins ps8_0_axi_periph/M04_ARESETN] \
    [get_bd_pins ps8_0_axi_periph/M05_ARESETN] \
    [get_bd_pins axi_dma_0/axi_resetn] \
    [get_bd_pins axi_gpio_ctrl/s_axi_aresetn] \
    [get_bd_pins axi_gpio_status/s_axi_aresetn] \
    [get_bd_pins axi_gpio_config/s_axi_aresetn] \
    [get_bd_pins axi_gpio_status2/s_axi_aresetn] \
    [get_bd_pins axi_gpio_flags/s_axi_aresetn]

# AXI data
connect_bd_intf_net [get_bd_intf_pins zynq_ultra_ps_e_0/M_AXI_HPM0_FPD] \
    [get_bd_intf_pins ps8_0_axi_periph/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins ps8_0_axi_periph/M00_AXI] [get_bd_intf_pins axi_dma_0/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins ps8_0_axi_periph/M01_AXI] [get_bd_intf_pins axi_gpio_ctrl/S_AXI]
connect_bd_intf_net [get_bd_intf_pins ps8_0_axi_periph/M02_AXI] [get_bd_intf_pins axi_gpio_status/S_AXI]
connect_bd_intf_net [get_bd_intf_pins ps8_0_axi_periph/M03_AXI] [get_bd_intf_pins axi_gpio_config/S_AXI]
connect_bd_intf_net [get_bd_intf_pins ps8_0_axi_periph/M04_AXI] [get_bd_intf_pins axi_gpio_status2/S_AXI]

connect_bd_intf_net [get_bd_intf_pins ps8_0_axi_periph/M05_AXI] [get_bd_intf_pins axi_gpio_flags/S_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_S2MM] \
    [get_bd_intf_pins zynq_ultra_ps_e_0/S_AXI_HP0_FPD]

# The DMA S2MM master may access PS DDR only. Explicitly map both DDR address
# segments and exclude unrelated QSPI/OCM windows from this master.
set dma_address_space [get_bd_addr_spaces axi_dma_0/Data_S2MM]
assign_bd_address -target_address_space $dma_address_space [get_bd_addr_segs zynq_ultra_ps_e_0/SAXIGP2/HP0_DDR_LOW]
assign_bd_address -target_address_space $dma_address_space [get_bd_addr_segs zynq_ultra_ps_e_0/SAXIGP2/HP0_DDR_HIGH]
exclude_bd_addr_seg -target_address_space $dma_address_space [get_bd_addr_segs zynq_ultra_ps_e_0/SAXIGP2/HP0_QSPI]
exclude_bd_addr_seg -target_address_space $dma_address_space [get_bd_addr_segs zynq_ultra_ps_e_0/SAXIGP2/HP0_LPS_OCM]

# Assign addresses only after all six slaves are connected to the PS master.
assign_bd_address -offset 0xA0000000 -range 64K [get_bd_addr_segs axi_dma_0/S_AXI_LITE/Reg]
assign_bd_address -offset 0xA0010000 -range 64K [get_bd_addr_segs axi_gpio_ctrl/S_AXI/Reg]
assign_bd_address -offset 0xA0020000 -range 64K [get_bd_addr_segs axi_gpio_status/S_AXI/Reg]
assign_bd_address -offset 0xA0030000 -range 64K [get_bd_addr_segs axi_gpio_config/S_AXI/Reg]
assign_bd_address -offset 0xA0040000 -range 64K [get_bd_addr_segs axi_gpio_status2/S_AXI/Reg]
assign_bd_address -offset 0xA0050000 -range 64K [get_bd_addr_segs axi_gpio_flags/S_AXI/Reg]

# DMA interrupt
connect_bd_net [get_bd_pins axi_dma_0/s2mm_introut] \
    [get_bd_pins zynq_ultra_ps_e_0/pl_ps_irq0]

} else {
    open_project $project_file
    open_bd_design [get_files -all ${bd_name}.bd]
}

# -----------------------------------------------------------------------------
# Validate, save, and wrap the editable template.
# -----------------------------------------------------------------------------
regenerate_bd_layout
validate_bd_design
save_bd_design
make_wrapper -files [get_files ${bd_name}.bd] -top
set wrapper_file [file join $build_dir ${proj_name}.gen sources_1 bd ${bd_name} hdl ${bd_name}_wrapper.v]
if {[llength [get_files -quiet $wrapper_file]] == 0} {
    add_files -norecurse $wrapper_file
}
set_property top ${bd_name}_wrapper [current_fileset]
generate_target all [get_files ${bd_name}.bd]

if {!$template_only} {
    # Export hardware metadata for PetaLinux without packaging a bitstream.
    set xsa_file [file normalize [expr {[info exists ::env(SCAM_XSA_OUTPUT)] ? $::env(SCAM_XSA_OUTPUT) : [file join $script_dir system.xsa]}]]
    write_hw_platform -fixed -force -file $xsa_file
    puts "XSA written to: $xsa_file"
}
