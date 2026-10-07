# =============================================================================
# SCAM application bitstream build
#
# Clones the editable base project, adds one application's RTL and constraints,
# sources its block-design edits, checks the PL contract, and writes a .bit.
# Normally run by scripts/build_hw.sh (make <app>-bitstream).
#
# Environment:
#   SCAM_APP_NAME       application name
#   SCAM_APP_HW_DIR     directory holding bd.tcl, src/, constraints/
#   SCAM_APP_BUILD_DIR  where the cloned Vivado project goes
#   SCAM_BITSTREAM_OUT  path of the .bit to write
#   SCAM_JOBS           parallel implementation jobs (default 8)
# =============================================================================

proc scam_env {name {default ""}} {
    if {[info exists ::env($name)] && $::env($name) ne ""} {
        return $::env($name)
    }
    if {$default eq ""} {
        error "SCAM: environment variable $name is not set"
    }
    return $default
}

set base_dir   [file dirname [file normalize [info script]]]
set app_name   [scam_env SCAM_APP_NAME]
set app_hw_dir [file normalize [scam_env SCAM_APP_HW_DIR]]
set build_dir  [file normalize [scam_env SCAM_APP_BUILD_DIR]]
set bit_file   [file normalize [scam_env SCAM_BITSTREAM_OUT]]
set jobs       [scam_env SCAM_JOBS 8]
set proj_name  scam_${app_name}

set bd_script [file join $app_hw_dir bd.tcl]
if {![file exists $bd_script]} {
    error "SCAM: $bd_script not found"
}

# The editable base Vivado project is the template. If needed, generate it
# once; then use Vivado's project-save operation to make this application's
# independent copy, so generated IP paths remain valid and changes saved in the
# template are inherited.
set base_project_xpr [file join $base_dir build scam_base_project scam_base.xpr]
if {![file exists $base_project_xpr]} {
    set ::SCAM_TEMPLATE_ONLY 1
    source [file join $base_dir build_base_xsa.tcl]
    unset ::SCAM_TEMPLATE_ONLY
    close_project
}
open_project $base_project_xpr
save_project_as -force -exclude_run_results $proj_name $build_dir
close_project
open_project [file join $build_dir ${proj_name}.xpr]

# Application sources. Module Reference in IP Integrator requires VHDL sources
# to be classified as standard VHDL, even when the RTL uses VHDL-2008.
set vhdl_files [glob -nocomplain -directory [file join $app_hw_dir src] *.vhd *.vhdl]
set other_files [glob -nocomplain -directory [file join $app_hw_dir src] *.v *.sv]
if {[llength $vhdl_files] + [llength $other_files] > 0} {
    add_files -norecurse [concat $vhdl_files $other_files]
}
if {[llength $vhdl_files] > 0} {
    set_property file_type VHDL [get_files $vhdl_files]
}
update_compile_order -fileset sources_1
set xdc_files [glob -nocomplain -directory [file join $app_hw_dir constraints] *.xdc]
if {[llength $xdc_files] > 0} {
    add_files -fileset constrs_1 -norecurse $xdc_files
}

open_bd_design [get_files base.bd]
# Available to bd.tcl: $app_name, $app_hw_dir.
source $bd_script

# -----------------------------------------------------------------------------
# PL contract (docs/pl-contract.md). The Linux image is built once from the
# base XSA, so an application must leave the AXI map, clocks, and DMA interrupt
# exactly as the base design has them.
# -----------------------------------------------------------------------------
proc scam_check_contract {} {
    set expected {
        /axi_dma_0/S_AXI_LITE/Reg     0xA0000000
        /axi_gpio_ctrl/S_AXI/Reg      0xA0010000
        /axi_gpio_status/S_AXI/Reg    0xA0020000
        /axi_gpio_config/S_AXI/Reg    0xA0030000
        /axi_gpio_status2/S_AXI/Reg   0xA0040000
        /axi_gpio_flags/S_AXI/Reg     0xA0050000
    }
    set problems {}

    set seen {}
    foreach seg [get_bd_addr_segs -of_objects [get_bd_addr_spaces zynq_ultra_ps_e_0/Data]] {
        set slave [get_bd_addr_segs -of_objects $seg]
        set offset [expr {[get_property OFFSET $seg]}]
        set range [expr {[get_property RANGE $seg]}]
        if {![dict exists $expected $slave]} {
            lappend problems [format "extra AXI peripheral %s at 0x%08X (applications may not add AXI slaves)" $slave $offset]
            continue
        }
        dict set seen $slave 1
        if {$offset != [dict get $expected $slave]} {
            lappend problems [format "%s is at 0x%08X, expected %s" $slave $offset [dict get $expected $slave]]
        }
        if {$range != 0x10000} {
            lappend problems [format "%s has range 0x%X, expected 0x10000" $slave $range]
        }
    }
    dict for {slave offset} $expected {
        if {![dict exists $seen $slave]} {
            lappend problems "$slave is missing from the PS address map (expected at $offset)"
        }
    }

    foreach {cell prop want what} {
        clk_wiz_0          CONFIG.CLKOUT1_REQUESTED_OUT_FREQ          400 "clk_wiz_0/clk_out1 (MHz)"
        clk_wiz_0          CONFIG.CLKOUT2_REQUESTED_OUT_FREQ          200 "clk_wiz_0/clk_out2 (MHz)"
        zynq_ultra_ps_e_0  CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ 100 "pl_clk0 (MHz)"
    } {
        set obj [get_bd_cells -quiet $cell]
        if {[llength $obj] == 0} {
            lappend problems "$cell is missing"
            continue
        }
        set got [get_property $prop $obj]
        if {$got != $want} {
            lappend problems "$what is $got, expected $want"
        }
    }

    set irq_net [get_bd_nets -quiet -of_objects [get_bd_pins -quiet zynq_ultra_ps_e_0/pl_ps_irq0]]
    set irq_pins [expr {[llength $irq_net] ? [get_bd_pins -of_objects $irq_net] : {}}]
    if {[lsort $irq_pins] ne [lsort {/axi_dma_0/s2mm_introut /zynq_ultra_ps_e_0/pl_ps_irq0}]} {
        lappend problems "pl_ps_irq0 must be driven by axi_dma_0/s2mm_introut only (found: $irq_pins)"
    }

    if {[llength $problems] > 0} {
        puts "ERROR: SCAM PL contract violated (see docs/pl-contract.md):"
        foreach p $problems {
            puts "ERROR:   - $p"
        }
        error "SCAM: PL contract violated: [join $problems {; }]"
    }
    puts "SCAM: PL contract check passed."
}

regenerate_bd_layout
validate_bd_design
scam_check_contract
save_bd_design
make_wrapper -files [get_files base.bd] -top -force
set_property top base_wrapper [current_fileset]
update_compile_order -fileset sources_1

launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "SCAM: implementation of '$app_name' failed; see the run logs under $build_dir"
}
open_run impl_1
file mkdir [file dirname $bit_file]
write_bitstream -force $bit_file
puts "SCAM: bitstream written to $bit_file"
